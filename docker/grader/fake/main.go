package main

import (
	"context"
	"crypto/sha1"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"html/template"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/omegaup/go-base/logging/log15"
	"github.com/omegaup/go-base/v3"
	"github.com/omegaup/go-base/v3/logging"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type Submissions struct {
	SubmissionID int    `gorm:"column:submission_id;primary"`
	GUID         string `gorm:"column:guid"`
	Problem      string
	Language     string
	Commit       string
	Version      string
	OldState     string
	OldVerdict   string `gorm:"column:old_verdict"`
	OldScore     float64
	OldRuntime   float64
	OldMemory    float64
	OldSyscalls  string
	NewState     string
	NewVerdict   string `gorm:"column:new_verdict"`
	NewScore     float64
	NewRuntime   float64
	NewMemory    float64
	NewSyscalls  string
}

type run struct {
	AttemptID      int     `json:"attempt_id"`
	Source         string  `json:"source"`
	Language       string  `json:"language"`
	Problem        string  `json:"problem"`
	Commit         string  `json:"commit"`
	InputHash      string  `json:"input_hash"`
	MaxScore       float64 `json:"max_score"`
	Debug          bool    `json:"debug"`
	SandboxVersion string  `json:"sandbox_version"`
}

type runMetadata struct {
	Verdict    string    `json:"verdict"`
	ExitStatus int       `json:"exit_status,omitempty"`
	Time       float64   `json:"time"`
	SystemTime float64   `json:"sys_time"`
	WallTime   float64   `json:"wall_time"`
	Memory     base.Byte `json:"memory"`
	Signal     *string   `json:"signal,omitempty"`
	Syscall    *string   `json:"syscall,omitempty"`
}

type runResult struct {
	Verdict      string                 `json:"verdict"`
	CompileError *string                `json:"compile_error,omitempty"`
	CompileMeta  map[string]runMetadata `json:"compile_meta"`
	Score        float64                `json:"score"`
	ContestScore float64                `json:"contest_score"`
	MaxScore     float64                `json:"max_score"`
	Time         float64                `json:"time"`
	WallTime     float64                `json:"wall_time"`
	Memory       base.Byte              `json:"memory"`
	JudgedBy     string                 `json:"judged_by,omitempty"`
	Groups       []groupResult          `json:"groups"`
}

type groupResult struct {
	Group        string       `json:"group"`
	Score        float64      `json:"score"`
	ContestScore float64      `json:"contest_score"`
	MaxScore     float64      `json:"max_score"`
	Cases        []caseResult `json:"cases"`
}

type caseResult struct {
	Verdict        string                 `json:"verdict"`
	Name           string                 `json:"name"`
	Score          float64                `json:"score"`
	ContestScore   float64                `json:"contest_score"`
	MaxScore       float64                `json:"max_score"`
	Meta           runMetadata            `json:"meta"`
	IndividualMeta map[string]runMetadata `json:"individual_meta,omitempty"`
}

type inputEntry struct {
	path        string
	problem     string
	version     string
	size        int64
	contentHash string
}

type inputManager struct {
	sync.RWMutex
	entries        map[string]inputEntry
	gitserverURL   *url.URL
	gitserverToken string
}

func newInputManager(gitserverURL string, gitserverToken string) (*inputManager, error) {
	files, err := os.ReadDir("cache")
	if err != nil {
		return nil, err
	}

	parsedGitserverURL, err := url.Parse(gitserverURL)
	if err != nil {
		return nil, err
	}

	result := &inputManager{
		entries:        make(map[string]inputEntry),
		gitserverURL:   parsedGitserverURL,
		gitserverToken: gitserverToken,
	}

	for _, file := range files {
		if file.IsDir() {
			continue
		}
		if strings.HasPrefix(file.Name(), ".") {
			os.Remove(path.Join("cache", file.Name()))
			continue
		}
		tokens := strings.Split(file.Name(), ".")
		if len(tokens) != 2 {
			return nil, fmt.Errorf("invalid entry: %s", file.Name())
		}
		problem := tokens[0]
		version := tokens[1]

		info, err := file.Info()
		if err != nil {
			return nil, fmt.Errorf("info: %w", err)
		}

		h := sha1.New()
		f, err := os.Open(path.Join("cache", file.Name()))
		if err != nil {
			return nil, fmt.Errorf("open: %w", err)
		}
		_, err = io.Copy(h, f)
		f.Close()
		if err != nil {
			return nil, fmt.Errorf("hash: %w", err)
		}

		result.entries[file.Name()] = inputEntry{
			path:        path.Join("cache", file.Name()),
			problem:     problem,
			version:     version,
			size:        info.Size(),
			contentHash: fmt.Sprintf("%0x", h.Sum(nil)),
		}
	}

	return result, nil
}

func (i *inputManager) get(problem, version string) (inputEntry, error) {
	key := fmt.Sprintf("%s.%s", problem, version)
	i.RLock()
	entry, ok := i.entries[key]
	i.RUnlock()
	if ok {
		return entry, nil
	}

	i.Lock()
	defer i.Unlock()

	f, err := os.CreateTemp("cache", "."+key)
	if err != nil {
		return inputEntry{}, err
	}
	requestURL := *i.gitserverURL
	requestURL.Path = fmt.Sprintf("/%s/+archive/%s.tar.gz", problem, version)
	req, err := http.NewRequest("GET", requestURL.String(), nil)
	if err != nil {
		f.Close()
		return inputEntry{}, fmt.Errorf("get problem: %w", err)
	}
	req.Header.Add("Authorization", fmt.Sprintf("OmegaUpSharedSecret %s omegaup:grader", i.gitserverToken))
	resp, err := (&http.Client{}).Do(req)
	if err != nil {
		f.Close()
		return inputEntry{}, fmt.Errorf("do get problem: %w", err)
	}
	h := sha1.New()
	size, err := io.Copy(io.MultiWriter(h, f), resp.Body)
	resp.Body.Close()
	closeErr := f.Close()
	if err != nil {
		return inputEntry{}, fmt.Errorf("get problem: %w", err)
	}
	if closeErr != nil {
		return inputEntry{}, fmt.Errorf("close input: %w", closeErr)
	}

	err = os.Rename(f.Name(), path.Join("cache", key))
	if err != nil {
		return inputEntry{}, fmt.Errorf("rename input: %w", err)
	}

	entry = inputEntry{
		path:        path.Join("cache", key),
		problem:     problem,
		version:     version,
		size:        size,
		contentHash: fmt.Sprintf("%0x", h.Sum(nil)),
	}
	i.entries[key] = entry

	return entry, nil
}

type handler struct {
	db           *gorm.DB
	dbLock       sync.RWMutex
	log          logging.Logger
	downloader   *s3manager.Downloader
	inputManager *inputManager
	htmlTemplate *template.Template
}

var _ http.Handler = (*handler)(nil)

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/run/request/" {
		h.handleRunRequest(w, r)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/run/") {
		h.handleRunResults(w, r)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/input/") {
		h.handleInput(w, r)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/submission/") {
		h.handleSubmission(w, r)
		return
	}
	if r.URL.Path == "/" {
		h.handleReport(w, r)
		return
	}
	w.WriteHeader(http.StatusNotFound)
}

func (h *handler) handleRunRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var submission Submissions
	h.dbLock.Lock()
	var before bool
	err := h.db.Transaction(func(tx *gorm.DB) error {
		err := tx.
			Where(`
				old_state IN ("new", "ready") AND
				new_state IN ("new", "ready") AND
				(old_state = "new" OR new_state = "new")
			`).
			Order("submission_id").
			First(&submission).Error
		if err != nil {
			return fmt.Errorf("find submission: %w", err)
		}
		before = submission.OldState == "new"
		if before {
			submission.OldState = "running"
			err := tx.
				Model(&Submissions{}).
				Where("submission_id", submission.SubmissionID).
				Update("old_state", submission.OldState).
				Error
			if err != nil {
				return fmt.Errorf("update old state: %w", err)
			}
		} else {
			submission.NewState = "running"
			err := tx.
				Model(&Submissions{}).
				Where("submission_id", submission.SubmissionID).
				Update("new_state", submission.NewState).
				Error
			if err != nil {
				return fmt.Errorf("update new state: %w", err)
			}
		}

		return nil
	})
	h.dbLock.Unlock()
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			h.log.Info("no more runs", nil)
			w.WriteHeader(http.StatusNotFound)
			return
		}
		h.log.Error("get run", map[string]interface{}{"error": err})
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	var b aws.WriteAtBuffer
	_, err = h.downloader.DownloadWithContext(r.Context(), &b, &s3.GetObjectInput{
		Bucket: aws.String("omegaup-backup"),
		Key:    aws.String(path.Join("omegaup/submissions", submission.GUID[:2], submission.GUID[2:])),
	})
	if err != nil {
		h.log.Error("get s3 object", map[string]interface{}{"error": err})
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	run := &run{
		Language:  submission.Language,
		Source:    string(b.Bytes()),
		Problem:   submission.Problem,
		Commit:    submission.Commit,
		InputHash: submission.Version,
		MaxScore:  1.0,
		Debug:     false,
	}
	if before {
		run.AttemptID = 10 * submission.SubmissionID
		run.SandboxVersion = "production"
	} else {
		run.AttemptID = 10*submission.SubmissionID + 1
		run.SandboxVersion = "3.7.0"
	}
	w.Header().Add("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	json.NewEncoder(w).Encode(run)
}

func (h *handler) handleRunResults(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	tokens := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(tokens) != 3 || tokens[2] != "results" {
		h.log.Error("bad tokens format", map[string]interface{}{"tokens": tokens})
		w.WriteHeader(http.StatusNotFound)
		return
	}

	submissionID, err := strconv.ParseInt(tokens[1], 10, 64)
	if err != nil {
		h.log.Error("parse submission id", map[string]interface{}{"error": err})
		w.WriteHeader(http.StatusNotFound)
		return
	}

	before := (submissionID % 10) == 0
	submissionID /= 10

	resultsDir := fmt.Sprintf("results/%d", submissionID)
	if before {
		resultsDir += "/before"
	} else {
		resultsDir += "/after"
	}
	err = os.MkdirAll(resultsDir, 0o755)
	if err != nil {
		h.log.Error("MkdirAll", map[string]interface{}{"error": err})
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	mediaType, params, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil {
		h.log.Error("ParseMediaType", map[string]interface{}{"error": err})
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if !strings.HasPrefix(mediaType, "multipart/") {
		h.log.Error("wrong media type", map[string]interface{}{"media type": mediaType})
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	mr := multipart.NewReader(r.Body, params["boundary"])
	for func() bool {
		p, err := mr.NextPart()
		if err != nil {
			if !errors.Is(err, io.EOF) {
				h.log.Error("next part", map[string]interface{}{"error": err})
			}
			return false
		}
		defer p.Close()
		if p.FileName() == ".keepalive" {
			return true
		}
		if p.FileName() != "details.json" {
			f, err := os.Create(path.Join(resultsDir, p.FileName()))
			if err != nil {
				h.log.Error("create file", map[string]interface{}{"error": err, "filename": p.FileName()})
				return true
			}
			defer f.Close()
			_, err = io.Copy(f, p)
			if err != nil {
				h.log.Error("write file", map[string]interface{}{"error": err, "filename": p.FileName()})
			}
			return true
		}

		// details.json.
		var results runResult
		err = json.NewDecoder(p).Decode(&results)
		if err != nil {
			h.log.Error("decode results", map[string]interface{}{"error": err, "filename": p.FileName()})
			return true
		}

		f, err := os.Create(path.Join(resultsDir, p.FileName()))
		if err != nil {
			h.log.Error("create file", map[string]interface{}{"error": err, "filename": p.FileName()})
			return true
		}
		defer f.Close()
		enc := json.NewEncoder(f)
		enc.SetIndent("", "  ")
		err = enc.Encode(&results)
		if err != nil {
			h.log.Error("write file", map[string]interface{}{"error": err, "filename": p.FileName()})
		}

		syscallsSet := make(map[string]struct{})
		for _, group := range results.Groups {
			for _, groupCase := range group.Cases {
				if groupCase.Meta.Syscall == nil {
					continue
				}
				syscallsSet[*groupCase.Meta.Syscall] = struct{}{}
			}
		}
		var syscalls []string
		for syscall := range syscallsSet {
			syscalls = append(syscalls, syscall)
		}

		h.dbLock.Lock()
		err = h.db.Transaction(func(tx *gorm.DB) error {
			var err error
			if before {
				err = tx.
					Model(&Submissions{}).
					Where("submission_id = ?", submissionID).
					Updates(map[string]interface{}{
						"old_state":    "ready",
						"old_verdict":  results.Verdict,
						"old_score":    results.Score,
						"old_runtime":  results.Time * 1000,
						"old_memory":   float64(results.Memory),
						"old_syscalls": strings.Join(syscalls, ","),
					}).
					Error
			} else {
				err = tx.
					Model(&Submissions{}).
					Where("submission_id = ?", submissionID).
					Updates(map[string]interface{}{
						"new_state":    "ready",
						"new_verdict":  results.Verdict,
						"new_score":    results.Score,
						"new_runtime":  results.Time * 1000,
						"new_memory":   float64(results.Memory),
						"new_syscalls": strings.Join(syscalls, ","),
					}).
					Error
			}
			if err != nil {
				return fmt.Errorf("update: %w", err)
			}

			return nil
		})
		h.dbLock.Unlock()
		if err != nil {
			h.log.Error("update submission", map[string]interface{}{"error": err, "filename": p.FileName()})
		}

		return true
	}() {
	}

	w.WriteHeader(http.StatusOK)
}

func (h *handler) handleInput(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	tokens := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(tokens) != 3 {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	problem := tokens[1]
	version := tokens[2]

	entry, err := h.inputManager.get(problem, version)
	if err != nil {
		h.log.Error("get input", map[string]interface{}{"error": err, "problem": problem, "version": version})
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	f, err := os.Open(entry.path)
	if err != nil {
		h.log.Error("open input", map[string]interface{}{"error": err, "problem": problem, "version": version, "entry": entry})
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	defer f.Close()

	w.Header().Add("Content-Type", "application/x-gzip")
	w.Header().Add("Content-Length", strconv.FormatInt(entry.size, 10))
	w.Header().Add("X-Content-Uncompressed-Size",
		strconv.FormatInt(entry.size, 10))
	w.Header().Add("Content-SHA1", entry.contentHash)
	w.WriteHeader(http.StatusOK)
	io.Copy(w, f)
}

func (h *handler) handleSubmission(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	tokens := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(tokens) < 3 || tokens[0] != "submission" {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	submissionID := tokens[1]

	if tokens[2] == "source" {
		var submission Submissions
		h.dbLock.Lock()
		err := h.db.Transaction(func(tx *gorm.DB) error {
			return tx.First(&submission, submissionID).Error
		})
		h.dbLock.Unlock()
		if err != nil {
			h.log.Error("find submission", map[string]interface{}{"error": err, "submissionID": submissionID})
			w.WriteHeader(http.StatusNotFound)
			return
		}
		var b aws.WriteAtBuffer
		_, err = h.downloader.DownloadWithContext(r.Context(), &b, &s3.GetObjectInput{
			Bucket: aws.String("omegaup-backup"),
			Key:    aws.String(path.Join("omegaup/submissions", submission.GUID[:2], submission.GUID[2:])),
		})
		if err != nil {
			h.log.Error("get s3 object", map[string]interface{}{"error": err, "submissionID": submissionID})
			w.WriteHeader(http.StatusNotFound)
			return
		}

		w.Header().Add("Content-Type", "text/plain")
		w.Header().Add("Content-Length", strconv.FormatInt(int64(len(b.Bytes())), 10))
		w.WriteHeader(http.StatusOK)
		w.Write(b.Bytes())
		return
	} else if tokens[2] == "details" {
		f, err := os.Open(path.Join("results", submissionID, "after/details.json"))
		if err != nil {
			h.log.Error("open details.json", map[string]interface{}{"error": err, "submissionID": submissionID})
			w.WriteHeader(http.StatusNotFound)
			return
		}
		defer f.Close()

		w.Header().Add("Content-Type", "text/json")
		w.WriteHeader(http.StatusOK)
		io.Copy(w, f)
		return
	} else if tokens[2] == "download" {
		f, err := os.Open(path.Join("results", submissionID, "after/files.zip"))
		if err != nil {
			h.log.Error("open files.zip", map[string]interface{}{"error": err, "submissionID": submissionID})
			w.WriteHeader(http.StatusNotFound)
			return
		}
		defer f.Close()

		w.Header().Add("Content-Type", "application/zip")
		w.WriteHeader(http.StatusOK)
		io.Copy(w, f)
		return
	} else if tokens[2] == "logs" {
		f, err := os.Open(path.Join("results", submissionID, "after/logs.txt"))
		if err != nil {
			h.log.Error("open logs.txt", map[string]interface{}{"error": err, "submissionID": submissionID})
			w.WriteHeader(http.StatusNotFound)
			return
		}
		defer f.Close()

		w.Header().Add("Content-Type", "text/plain")
		w.WriteHeader(http.StatusOK)
		io.Copy(w, f)
		return
	}

	w.WriteHeader(http.StatusNotFound)
	return
}

func (h *handler) handleReport(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	report, err := generateReport(h.db, h.htmlTemplate, r.URL.Query())
	if err != nil {
		h.log.Error("generate report", map[string]interface{}{"error": err})
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.Header().Add("Content-Type", "text/html")
	w.Header().Add("Content-Length", strconv.Itoa(len(report)))
	w.WriteHeader(http.StatusOK)
	w.Write(report)
}

type responseWriter struct {
	w      http.ResponseWriter
	status int
}

var _ http.ResponseWriter = (*responseWriter)(nil)

func (w *responseWriter) WriteHeader(status int) {
	w.status = status
	w.w.WriteHeader(status)
}

func (w *responseWriter) Header() http.Header {
	return w.w.Header()
}

func (w *responseWriter) Write(b []byte) (int, error) {
	return w.w.Write(b)
}

func loggingMiddleware(log logging.Logger, handler http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rw := &responseWriter{w: w, status: http.StatusNotFound}
		defer func() {
			if rw.status == http.StatusOK {
				log.Info("ServeHTTP", map[string]interface{}{
					"method": r.Method,
					"path":   r.URL.Path,
					"status": rw.status,
				})
			} else {
				log.Warn("ServeHTTP", map[string]interface{}{
					"method": r.Method,
					"path":   r.URL.Path,
					"status": rw.status,
				})
			}
		}()
		handler.ServeHTTP(rw, r)
	})
}

func main() {
	port := flag.Int("port", 11302, "Port at which the grader listens")
	gitserverURL := flag.String("gitserver-url", "http://gitserver-service:33861/", "The gitserver token")
	gitserverToken := flag.String("gitserver-token", "", "The gitserver token")
	databaseName := flag.String("database", "submissions.db", "The database")
	report := flag.Bool("report", false, "Only run the report")
	flag.Parse()

	log, err := log15.New("info", false)
	if err != nil {
		panic(err)
	}

	htmlTemplate, err := template.ParseGlob("templates/*.html")
	if err != nil {
		log.Error("parse template", map[string]interface{}{"error": err})
		os.Exit(1)
	}

	db, err := gorm.Open(sqlite.Open(*databaseName), &gorm.Config{
		SkipDefaultTransaction: true,
	})
	if err != nil {
		log.Error("open database", map[string]interface{}{"error": err})
		os.Exit(1)
	}

	if *report {
		report, err := generateReport(db, htmlTemplate, nil)
		if err != nil {
			log.Error("generate report", map[string]interface{}{"error": err})
			os.Exit(1)
		}
		fmt.Println(string(report))
		return
	}

	log.Info("Starting fake_grader", nil)

	sess := session.Must(session.NewSession(&aws.Config{
		Region: aws.String("us-east-1"),
	}))
	downloader := s3manager.NewDownloader(sess)

	inputManager, err := newInputManager(*gitserverURL, *gitserverToken)
	if err != nil {
		log.Error("initialize input manager", map[string]interface{}{"error": err})
		os.Exit(1)
	}

	err = db.Model(&Submissions{}).Where("old_state != ?", "ready").Update("old_state", "new").Error
	if err != nil {
		log.Error("reset old_state", map[string]interface{}{"error": err})
		os.Exit(1)
	}
	err = db.Model(&Submissions{}).Where("new_state != ?", "ready").Update("new_state", "new").Error
	if err != nil {
		log.Error("reset old_state", map[string]interface{}{"error": err})
		os.Exit(1)
	}

	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, syscall.SIGINT, syscall.SIGTERM)

	s := http.Server{
		Addr: fmt.Sprintf(":%d", *port),
		Handler: loggingMiddleware(log, &handler{
			db:           db,
			log:          log,
			downloader:   downloader,
			inputManager: inputManager,
			htmlTemplate: htmlTemplate,
		}),
	}
	serverDone := make(chan struct{})
	go func() {
		defer close(serverDone)
		err = s.ListenAndServeTLS("certificate.pem", "key.pem")
		if err != nil {
			if !errors.Is(err, http.ErrServerClosed) {
				log.Error("listen and serve", map[string]interface{}{"error": err})
				os.Exit(1)
			}
		}
	}()

	log.Info(fmt.Sprintf("listening at :%d", *port), nil)
	<-stopChan

	log.Info("Shutting down fake_grader...", nil)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	s.Shutdown(ctx)
	<-serverDone

	log.Info("fake_grader cleanly shut down", nil)
}
