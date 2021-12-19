package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"

	"github.com/omegaup/go-base/logging/log15"
	"github.com/omegaup/go-base/v3/logging"
)

const (
	bucketMetadataKey = "bucket-metadata.json"
)

type bucketMetadata struct {
	LastUpdated time.Time `json:"lastUpdated"`
}

type fileToBackup struct {
	path       string
	bucketName string
	bucketKey  string
	modTime    time.Time
	done       chan<- error
}

type backuper struct {
	downloader *s3manager.Downloader
	uploader   *s3manager.Uploader
	uploadChan chan *fileToBackup
}

func (b *backuper) uploadJob(ctx context.Context, noop bool) {
	for fileToBackup := range b.uploadChan {
		fileToBackup.done <- (func() error {
			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			f, err := os.Open(fileToBackup.path)
			if err != nil {
				return err
			}
			defer f.Close()

			uploadInput := &s3manager.UploadInput{
				Body:   f,
				Key:    aws.String(fileToBackup.bucketKey),
				Bucket: aws.String(fileToBackup.bucketName),
			}
			if !noop {
				_, err = b.uploader.UploadWithContext(aws.Context(ctx), uploadInput)
				if err != nil {
					return fmt.Errorf("put s3://%s/%s: %w", *uploadInput.Bucket, *uploadInput.Key, err)
				}
			}
			return nil
		})()
		close(fileToBackup.done)
	}
}

func (b *backuper) getBucketMetadata(bucketName string, bucketPrefix string) (bucketMetadata, error) {
	var runsMetadata bucketMetadata
	var runsMetadataBuffer aws.WriteAtBuffer
	_, err := b.downloader.Download(&runsMetadataBuffer, &s3.GetObjectInput{
		Bucket: aws.String(bucketName),
		Key:    aws.String(path.Join(bucketPrefix, bucketMetadataKey)),
	})
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok && aerr.Code() == "NoSuchKey" {
			// This is fine.
			return runsMetadata, nil
		}
		return runsMetadata, fmt.Errorf("download s3://%s/%s: %w", bucketName, bucketMetadataKey, err)
	}
	err = json.Unmarshal(runsMetadataBuffer.Bytes(), &runsMetadata)
	if err != nil {
		return runsMetadata, fmt.Errorf("unmashal metadata: %w", err)
	}
	return runsMetadata, nil
}

func (b *backuper) backup(
	ctx context.Context,
	log logging.Logger,
	noop bool,
	root string,
	bucketName string,
	bucketPrefix string,
	keyNameFunc func(backupPrefix string, relpath string) string,
) error {
	currentBucketMetadata, err := b.getBucketMetadata(bucketName, bucketPrefix)
	if err != nil {
		return fmt.Errorf("get bucket metadata: %w", err)
	}
	lastUpdated := currentBucketMetadata.LastUpdated
	log.Info("starting upload", map[string]interface{}{"lastUpdated": lastUpdated})

	defer func() {
		if lastUpdated == currentBucketMetadata.LastUpdated {
			log.Info("nothing was uploaded", map[string]interface{}{"lastUpdated": lastUpdated})
			return
		}
		log.Info("done uploading", map[string]interface{}{"lastUpdated": lastUpdated})
		finalBucketMetadata := bucketMetadata{
			LastUpdated: lastUpdated,
		}
		finalBucketMetadataJSON, err := json.Marshal(&finalBucketMetadata)
		if err != nil {
			log.Error("marshal bucket metadata", map[string]interface{}{"error": err})
			return
		}

		uploadInput := &s3manager.UploadInput{
			Body:   bytes.NewReader(finalBucketMetadataJSON),
			Key:    aws.String(path.Join(bucketPrefix, bucketMetadataKey)),
			Bucket: aws.String(bucketName),
		}
		_, err = b.uploader.UploadWithContext(aws.Context(ctx), uploadInput)
		if err != nil {
			log.Error("put bucket metadata", map[string]interface{}{"error": err})
			return
		}
		log.Info("saved bucket metadata", map[string]interface{}{"lastUpdated": lastUpdated})
	}()

	// Enumerate all files.
	var filesToBackup []*fileToBackup
	err = filepath.WalkDir(root, func(walkPath string, d fs.DirEntry, err error) error {
		if err != nil {
			return fmt.Errorf("walkdir: %w", err)
		}
		if d.IsDir() {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		info, err := d.Info()
		if err != nil {
			return fmt.Errorf("info: %w", err)
		}
		if info.ModTime().Before(lastUpdated) {
			return nil
		}

		relPath, err := filepath.Rel(root, walkPath)
		if err != nil {
			return fmt.Errorf("rel: %w", err)
		}

		filesToBackup = append(filesToBackup, &fileToBackup{
			path:       walkPath,
			bucketName: bucketName,
			bucketKey:  keyNameFunc(bucketPrefix, relPath),
			modTime:    info.ModTime(),
		})
		return nil
	})
	if err != nil {
		return err
	}

	sort.Slice(filesToBackup, func(i, j int) bool {
		return filesToBackup[i].modTime.Before(filesToBackup[j].modTime)
	})
	for _, fileToBackup := range filesToBackup {
		err := (func() error {
			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			done := make(chan error, 1)
			fileToBackup.done = done
			log.Info("uploading file", map[string]interface{}{
				"path":   fileToBackup.path,
				"object": fmt.Sprintf("s3://%s/%s", bucketName, fileToBackup.bucketKey),
			})
			b.uploadChan <- fileToBackup

			select {
			case <-ctx.Done():
				return ctx.Err()
			case err := <-done:
				if err != nil {
					return err
				}
			}

			if !noop {
				lastUpdated = fileToBackup.modTime
			}
			return nil
		})()

		if err != nil {
			return fmt.Errorf("backup: %w", err)
		}
	}

	return nil
}

func main() {
	noop := flag.Bool("noop", false, "Does not perform any uploads")
	backupSubmissions := flag.Bool("backup-submissions", true, "Backup submissions")
	backupRuns := flag.Bool("backup-runs", true, "Backup runs")
	workers := flag.Int("workers", 4, "Number of concurrent upload jobs")
	flag.Parse()

	log, err := log15.New("info", true)
	if err != nil {
		panic(err)
	}

	sess, err := session.NewSession(
		aws.NewConfig().
			WithHTTPClient(&http.Client{
				Timeout: 5 * time.Minute,
				Transport: &http.Transport{
					Dial: (&net.Dialer{
						Timeout:   30 * time.Second,
						KeepAlive: 30 * time.Second,
					}).Dial,
					TLSHandshakeTimeout:   10 * time.Second,
					ResponseHeaderTimeout: 10 * time.Second,
					ExpectContinueTimeout: 1 * time.Second,
				},
			}).
			WithLogLevel(aws.LogOff).
			WithLogger(aws.LoggerFunc(func(args ...interface{}) {
				log.Debug(fmt.Sprintln(args...), nil)
			})),
	)
	if err != nil {
		log.Error("aws session", map[string]interface{}{"error": err})
		os.Exit(1)
	}

	b := backuper{
		downloader: s3manager.NewDownloader(sess),
		uploader:   s3manager.NewUploader(sess),
		uploadChan: make(chan *fileToBackup, *workers),
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var workersWG sync.WaitGroup
	for i := 0; i < *workers; i++ {
		workersWG.Add(1)
		go func() {
			defer workersWG.Done()
			b.uploadJob(ctx, *noop)
		}()
	}

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigs
		log.Info("received signal, shutting down", map[string]interface{}{"signal": sig})
		cancel()
	}()

	var failed bool
	defer func() {
		if failed {
			os.Exit(1)
		}
	}()

	var wg sync.WaitGroup
	if *backupSubmissions {
		wg.Add(1)
		log = log.New(map[string]interface{}{"backup": "submissions"})
		go func() {
			defer wg.Done()
			err = b.backup(
				ctx,
				log,
				*noop,
				"/var/lib/omegaup/submissions",
				"omegaup-backup",
				"omegaup/submissions",
				func(backupPrefix string, relpath string) string {
					return path.Join(backupPrefix, relpath)
				},
			)
			if err != nil {
				log.Error("backup failed", map[string]interface{}{"error": err})
				failed = true
			}
		}()
	}

	if *backupRuns {
		wg.Add(1)
		log = log.New(map[string]interface{}{"backup": "runs"})
		go func() {
			defer wg.Done()
			err = b.backup(
				ctx,
				log,
				*noop,
				"/var/lib/omegaup/grade",
				"omegaup-runs",
				"",
				func(backupPrefix string, relpath string) string {
					segments := strings.SplitN(relpath, "/", 3)
					return path.Join(backupPrefix, segments[2])
				},
			)
			if err != nil {
				log.Error("backup failed", map[string]interface{}{"error": err})
				failed = true
			}
		}()
	}

	wg.Wait()
	close(b.uploadChan)
	workersWG.Wait()
}
