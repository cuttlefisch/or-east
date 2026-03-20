;;; test-or-east.el --- Buttercup specs for or-east -*- lexical-binding: t; -*-
;;; Commentary:
;;
;; Buttercup test suite for or-east-mode.  Covers time formatting, file
;; utilities, body hashing, property updates (last-accessed, last-modified),
;; hook setup, minor mode lifecycle, customization variables, date parsing,
;; activity scoring, and sort-by-activity integration.
;;
;;; Code:

(require 'test-helper)

;;; or-east-node-time-string-now

(describe "or-east-node-time-string-now"
  (it "returns a formatted time string using the default format"
    (let ((result (or-east-node-time-string-now)))
      (expect result :to-match "^[0-9][0-9]/[0-9][0-9]/[0-9][0-9]$")))

  (it "accepts a custom format string"
    (let ((result (or-east-node-time-string-now "%Y")))
      (expect result :to-match "^[0-9]\\{4\\}$"))))

;;; or-east-node-get-string-of-file

(describe "or-east-node-get-string-of-file"
  (it "returns file contents as a string"
    (with-or-east-test-file "hello world"
      (expect (or-east-node-get-string-of-file temp-file)
              :to-equal "hello world")))

  (it "returns empty string for nil path"
    (expect (or-east-node-get-string-of-file nil) :to-equal ""))

  (it "returns empty string for nonexistent path"
    (expect (or-east-node-get-string-of-file "/tmp/nonexistent-or-east-file.org")
            :to-equal "")))

;;; or-east-node-body-hash

(describe "or-east-node-body-hash"
  (it "returns a hash string for a file with a title"
    (with-or-east-test-file or-east-test-org-content
      (let ((hash (or-east-node-body-hash temp-file)))
        (expect hash :to-be-truthy)
        (expect (stringp hash) :to-be-truthy))))

  (it "returns the same hash for identical content"
    (with-or-east-test-file or-east-test-org-content
      (let ((hash1 (or-east-node-body-hash temp-file))
            (hash2 (or-east-node-body-hash temp-file)))
        (expect hash1 :to-equal hash2))))

  (it "returns different hashes for different content"
    (with-or-east-test-file "#+title: A\nBody A"
      (let ((hash-a (or-east-node-body-hash temp-file)))
        (with-or-east-test-file "#+title: B\nBody B"
          (let ((hash-b (or-east-node-body-hash temp-file)))
            (expect hash-a :not :to-equal hash-b)))))))

;;; or-east-node-update-stats

(describe "or-east-node-update-stats"
  (it "updates hash and last-modified when buffer is an org-roam buffer"
    (with-or-east-test-file or-east-test-org-content
      (spy-on 'org-roam-buffer-p :and-return-value t)
      (spy-on 'org-roam-node-from-id :and-return-value nil)
      (with-current-buffer (find-file-noselect temp-file)
        (unwind-protect
            (progn
              (or-east-node-update-stats)
              (let ((hash (car (org-property-values "hash")))
                    (modified (car (org-property-values "last-modified"))))
                (expect hash :to-be-truthy)
                (expect modified :to-be-truthy)))
          (kill-buffer)))))

  (it "does nothing when buffer is not an org-roam buffer"
    (with-or-east-test-file or-east-test-org-content
      (spy-on 'org-roam-buffer-p :and-return-value nil)
      (with-current-buffer (find-file-noselect temp-file)
        (unwind-protect
            (progn
              (or-east-node-update-stats)
              (expect (car (org-property-values "hash")) :to-be nil))
          (kill-buffer))))))

;;; or-east-node-update-access-time-by-id

(describe "or-east-node-update-access-time-by-id"
  (it "sets last-accessed property on the current buffer"
    (with-or-east-test-file or-east-test-org-content
      (spy-on 'org-roam-node-from-id :and-return-value nil)
      (with-current-buffer (find-file-noselect temp-file)
        (unwind-protect
            (progn
              (or-east-node-update-access-time-by-id)
              (expect (car (org-property-values "last-accessed")) :to-be-truthy))
          (kill-buffer))))))

;;; or-east--setup-modified-tracking

(describe "or-east--setup-modified-tracking"
  (it "adds or-east-node-update-stats to buffer-local after-save-hook"
    (with-temp-buffer
      (or-east--setup-modified-tracking)
      (expect (memq #'or-east-node-update-stats after-save-hook) :to-be-truthy))))

;;; or-east-mode

(describe "or-east-mode"
  (it "adds hooks when enabled"
    (with-temp-buffer
      (or-east-mode +1)
      (expect (memq #'or-east-node-update-access-time-by-id
                    org-roam-find-file-hook) :to-be-truthy)
      (expect (memq #'or-east--setup-modified-tracking
                    org-roam-find-file-hook) :to-be-truthy)
      (expect (memq #'or-east-node-update-link-time-by-id
                    org-roam-post-node-insert-hook) :to-be-truthy)
      ;; Clean up
      (or-east-mode -1)))

  (it "removes hooks when disabled"
    (with-temp-buffer
      (or-east-mode +1)
      (or-east-mode -1)
      (expect (memq #'or-east-node-update-access-time-by-id
                    org-roam-find-file-hook) :not :to-be-truthy)
      (expect (memq #'or-east--setup-modified-tracking
                    org-roam-find-file-hook) :not :to-be-truthy)
      (expect (memq #'or-east-node-update-link-time-by-id
                    org-roam-post-node-insert-hook) :not :to-be-truthy)))

  (it "has an or-east defgroup"
    (expect (get 'or-east 'custom-group) :to-be-truthy)))

;;; or-east-enable / or-east-disable

(describe "or-east-enable"
  (it "activates or-east-mode"
    (with-temp-buffer
      (or-east-enable)
      (expect or-east-mode :to-be-truthy)
      (or-east-mode -1))))

(describe "or-east-disable"
  (it "deactivates or-east-mode"
    (with-temp-buffer
      (or-east-enable)
      (or-east-disable)
      (expect or-east-mode :not :to-be-truthy))))

;;; customization

(describe "customization"
  (it "defines or-east-node-stat-format-time-string"
    (expect (boundp 'or-east-node-stat-format-time-string) :to-be-truthy)
    (expect or-east-node-stat-format-time-string :to-equal "%D"))

  (it "defines or-east-activity-weights"
    (expect (boundp 'or-east-activity-weights) :to-be-truthy)
    (expect or-east-activity-weights :to-be-truthy)
    (expect (assq 'last-accessed or-east-activity-weights) :to-be-truthy)
    (expect (assq 'last-modified or-east-activity-weights) :to-be-truthy)
    (expect (assq 'last-linked or-east-activity-weights) :to-be-truthy))

  (it "defines or-east-activity-decay-rate"
    (expect (boundp 'or-east-activity-decay-rate) :to-be-truthy)
    (expect or-east-activity-decay-rate :to-equal 0.01)))

;;; or-east--parse-date

(describe "or-east--parse-date"
  (it "parses a valid MM/DD/YY date to days since epoch"
    (let ((days (or-east--parse-date "03/20/26")))
      (expect days :to-be-truthy)
      (expect (integerp days) :to-be-truthy)
      (expect (> days 0) :to-be-truthy)))

  (it "returns nil for the zero sentinel 00/00/00"
    (expect (or-east--parse-date "00/00/00") :to-be nil))

  (it "returns nil for nil input"
    (expect (or-east--parse-date nil) :to-be nil))

  (it "returns nil for empty string"
    (expect (or-east--parse-date "") :to-be nil))

  (it "returns nil for malformed dates"
    (expect (or-east--parse-date "2026-03-20") :to-be nil)
    (expect (or-east--parse-date "not-a-date") :to-be nil))

  (it "parses dates in chronological order"
    (let ((earlier (or-east--parse-date "01/01/25"))
          (later   (or-east--parse-date "06/15/25")))
      (expect earlier :to-be-truthy)
      (expect later :to-be-truthy)
      (expect (< earlier later) :to-be-truthy))))

;;; or-east-node-activity-score

(describe "or-east-node-activity-score"
  (it "returns 0.0 for a node with no or-east properties"
    (let ((node (or-east-test-node-create :properties '(("CATEGORY" . "test")))))
      (expect (or-east-node-activity-score node) :to-equal 0.0)))

  (it "returns 0.0 for a node with only zero-sentinel dates"
    (let ((node (or-east-test-node-create
                 :properties '(("LAST-ACCESSED" . "00/00/00")
                               ("LAST-MODIFIED" . "00/00/00")
                               ("LAST-LINKED"   . "00/00/00")))))
      (expect (or-east-node-activity-score node) :to-equal 0.0)))

  (it "returns a positive score for a node with valid dates"
    (let ((node (or-east-test-node-create
                 :properties '(("LAST-ACCESSED" . "03/20/26")
                               ("LAST-MODIFIED" . "03/20/26")
                               ("LAST-LINKED"   . "03/15/26")))))
      (expect (> (or-east-node-activity-score node) 0.0) :to-be-truthy)))

  (it "scores recently modified nodes higher than old ones"
    (let ((recent (or-east-test-node-create
                   :properties '(("LAST-MODIFIED" . "03/20/26"))))
          (old    (or-east-test-node-create
                   :properties '(("LAST-MODIFIED" . "01/01/23")))))
      (expect (> (or-east-node-activity-score recent)
                 (or-east-node-activity-score old))
              :to-be-truthy)))

  (it "weights last-modified higher than last-accessed"
    (let ((modified-only (or-east-test-node-create
                          :properties '(("LAST-MODIFIED" . "03/20/26"))))
          (accessed-only (or-east-test-node-create
                          :properties '(("LAST-ACCESSED" . "03/20/26")))))
      (expect (> (or-east-node-activity-score modified-only)
                 (or-east-node-activity-score accessed-only))
              :to-be-truthy)))

  (it "respects custom weights"
    (let ((or-east-activity-weights '((last-accessed . 10.0)
                                      (last-modified . 0.0)
                                      (last-linked   . 0.0)))
          (node (or-east-test-node-create
                 :properties '(("LAST-ACCESSED" . "03/20/26")
                               ("LAST-MODIFIED" . "03/20/26")))))
      ;; With modified weight zeroed, only accessed contributes
      (expect (> (or-east-node-activity-score node) 0.0) :to-be-truthy)))

  (it "respects custom decay rate"
    (let ((node (or-east-test-node-create
                 :properties '(("LAST-ACCESSED" . "01/01/24")))))
      (let* ((or-east-activity-decay-rate 0.001)
             (slow-decay (or-east-node-activity-score node)))
        (let* ((or-east-activity-decay-rate 0.1)
               (fast-decay (or-east-node-activity-score node)))
          (expect (> slow-decay fast-decay) :to-be-truthy))))))

;;; or-east-node-sort-by-activity

(describe "or-east-node-sort-by-activity"
  (it "sorts more active nodes first"
    (let* ((recent-node (or-east-test-node-create
                         :properties '(("LAST-MODIFIED" . "03/20/26"))))
           (old-node    (or-east-test-node-create
                         :properties '(("LAST-MODIFIED" . "01/01/23"))))
           (comp-a (cons "Recent" recent-node))
           (comp-b (cons "Old" old-node)))
      (expect (or-east-node-sort-by-activity comp-a comp-b) :to-be-truthy)
      (expect (or-east-node-sort-by-activity comp-b comp-a) :not :to-be-truthy)))

  (it "is registered as org-roam-node-read-sort-by-activity"
    (expect (fboundp 'org-roam-node-read-sort-by-activity) :to-be-truthy)))

(provide 'test-or-east)
;;; test-or-east.el ends here
