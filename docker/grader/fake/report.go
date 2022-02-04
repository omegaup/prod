package main

import (
	"bytes"
	"fmt"
	"html/template"
	"net/url"
	"strings"

	"gorm.io/gorm"
)

func generateReport(db *gorm.DB, htmlTemplate *template.Template, params url.Values) ([]byte, error) {
	verdicts := []string{
		"CE",
		"PA",
		"WA",
		"AC",
		"MLE",
		"OLE",
		"TLE",
		"RFE",
		"RTE",
		"JE",
		"VE",
	}
	var scoreFilter string
	if len(params["score"]) > 0 {
		scoreFilter = params["score"][0]
	}
	var languageFilter string
	if len(params["language"]) > 0 {
		languageFilter = params["language"][0]
	}
	var oldVerdictFilter string
	if len(params["old_verdict"]) > 0 {
		oldVerdictFilter = params["old_verdict"][0]
	}
	var newVerdictFilter string
	if len(params["new_verdict"]) > 0 {
		newVerdictFilter = params["new_verdict"][0]
	}
	var progress float64
	var better, same, worse int
	confusion := make(map[string]map[string]int)
	var submissions []Submissions
	err := db.Transaction(func(tx *gorm.DB) error {
		clauses := []string{"old_state = @state", "new_state = @state"}
		arguments := map[string]interface{}{"state": "ready"}
		err := tx.
			Raw(
				fmt.Sprintf(
					`
					SELECT
						100 * (SELECT COUNT(*) FROM Submissions WHERE %[1]s) /
						(SELECT COUNT(*) FROM Submissions) as progress;
					`,
					strings.Join(clauses, " AND "),
				),
				arguments,
			).
			Row().
			Scan(&progress)
		if err != nil {
			return fmt.Errorf("get progress: %w", err)
		}

		if languageFilter != "" {
			clauses = append(clauses, "language = @language")
			arguments["language"] = languageFilter
		}
		if oldVerdictFilter != "" {
			clauses = append(clauses, "old_verdict = @old_verdict")
			arguments["old_verdict"] = oldVerdictFilter
		}
		if newVerdictFilter != "" {
			clauses = append(clauses, "new_verdict = @new_verdict")
			arguments["new_verdict"] = newVerdictFilter
		}

		err = tx.
			Raw(
				fmt.Sprintf(
					`
					SELECT
						(
							SELECT COUNT(*)
							FROM Submissions
							WHERE
								%[1]s AND
								new_score > old_score + 0.005
						) as better,
						(
							SELECT COUNT(*)
							FROM Submissions
							WHERE
								%[1]s AND
								new_score >= old_score - 0.005 AND
								new_score <= old_score + 0.005
						) as same,
						(
							SELECT COUNT(*)
							FROM Submissions
							WHERE
								%[1]s AND
								new_score < old_score - 0.005
						) as worse;
					`,
					strings.Join(clauses, " AND "),
				),
				arguments,
			).
			Row().
			Scan(&better, &same, &worse)
		if err != nil {
			return fmt.Errorf("better, same, worse: %w", err)
		}

		if scoreFilter == "same" {
			clauses = append(clauses, "new_score >= old_score - 0.005", "new_score <= old_score + 0.005")
		} else if scoreFilter == "better" {
			clauses = append(clauses, "new_score > old_score + 0.005")
		} else if scoreFilter == "worse" {
			clauses = append(clauses, "new_score < old_score - 0.005")
		}

		confusion["TOTAL"] = make(map[string]int)
		for _, verdict := range verdicts {
			confusion[verdict] = make(map[string]int)
		}

		rows, err := tx.
			Raw(
				fmt.Sprintf(
					`
					SELECT
						old_verdict,
						new_verdict,
						COUNT(*) AS c
					FROM Submissions
					WHERE %[1]s
					GROUP BY old_verdict, new_verdict;
					`,
					strings.Join(clauses, " AND "),
				),
				arguments,
			).
			Rows()
		if err != nil {
			return fmt.Errorf("confusion: %w", err)
		}
		for rows.Next() {
			var oldVerdict, newVerdict string
			var c int
			err = rows.Scan(&oldVerdict, &newVerdict, &c)
			if err != nil {
				return fmt.Errorf("confusion scan: %w", err)
			}
			confusion[oldVerdict][newVerdict] += c
			confusion[oldVerdict]["TOTAL"] += c
			confusion["TOTAL"][newVerdict] += c
		}

		err = tx.
			Raw(
				fmt.Sprintf(
					`
					SELECT
						submission_id,
						guid,
						language,
						problem,
						old_verdict,
						old_score * 100 as old_score,
						old_runtime,
						old_memory / 1024 / 1024 as old_memory,
						old_syscalls,
						new_verdict,
						new_score * 100 as new_score,
						new_runtime,
						new_memory / 1024 / 1024 as new_memory,
						new_syscalls
					FROM Submissions
					WHERE %[1]s
					ORDER BY submission_id
					LIMIT 0, 1000;
					`,
					strings.Join(clauses, " AND "),
				),
				arguments,
			).
			Find(&submissions).
			Error
		if err != nil {
			return fmt.Errorf("submissions: %w", err)
		}

		return nil
	})
	if err != nil {
		return nil, err
	}

	var betterPercent, samePercent, worsePercent float64
	totalRuns := better + same + worse
	if totalRuns != 0 {
		betterPercent = 100.0 * float64(better) / float64(totalRuns)
		samePercent = 100.0 * float64(same) / float64(totalRuns)
		worsePercent = 100.0 * float64(worse) / float64(totalRuns)
	}

	data := struct {
		Verdicts  []string
		Languages []struct {
			Value string
			Name  string
		}
		Score         string
		Language      string
		OldVerdict    string
		NewVerdict    string
		Progress      float64
		Better        int
		Same          int
		Worse         int
		TotalRuns     int
		BetterPercent float64
		SamePercent   float64
		WorsePercent  float64
		Confusion     map[string]map[string]int
		Submissions   []Submissions
	}{
		Verdicts: verdicts,
		Languages: []struct {
			Value string
			Name  string
		}{
			{"", "All languages"},
			{"c", "C"},
			{"cpp", "C++"},
			{"cpp11", "C++ 11"},
			{"cat", "Sólo Salida"},
			{"hs", "Haskell"},
			{"java", "Java"},
			{"kj", "Karel Java"},
			{"kp", "Karel Pascal"},
			{"pas", "Pascal"},
			{"py2", "Python 2.7"},
			{"py3", "Python 3"},
			{"rb", "Ruby"},
		},
		Score:         scoreFilter,
		Language:      languageFilter,
		OldVerdict:    oldVerdictFilter,
		NewVerdict:    newVerdictFilter,
		Progress:      progress,
		Better:        better,
		Same:          same,
		Worse:         worse,
		TotalRuns:     better + same + worse,
		BetterPercent: betterPercent,
		SamePercent:   samePercent,
		WorsePercent:  worsePercent,
		Confusion:     confusion,
		Submissions:   submissions,
	}
	var buf bytes.Buffer
	err = htmlTemplate.Execute(&buf, data)
	if err != nil {
		return nil, fmt.Errorf("render template: %w", err)
	}
	return buf.Bytes(), nil
}
