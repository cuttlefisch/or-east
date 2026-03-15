;;; test-or-east.el --- Buttercup specs for or-east -*- lexical-binding: t; -*-
;;; Commentary:
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

;;; or-east-node-handle-modified-time-tracking-h

(describe "or-east-node-handle-modified-time-tracking-h"
  (it "adds or-east-node-update-stats to buffer-local after-save-hook"
    (with-temp-buffer
      (or-east-node-handle-modified-time-tracking-h)
      (expect (memq #'or-east-node-update-stats after-save-hook) :to-be-truthy))))

;;; or-east-mode

(describe "or-east-mode"
  (it "adds hooks when enabled"
    (with-temp-buffer
      (or-east-mode +1)
      (expect (memq #'or-east-node-update-access-time-by-id
                    org-roam-find-file-hook) :to-be-truthy)
      (expect (memq #'or-east-node-handle-modified-time-tracking-h
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
      (expect (memq #'or-east-node-handle-modified-time-tracking-h
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
    (expect or-east-node-stat-format-time-string :to-equal "%D")))

(provide 'test-or-east)
;;; test-or-east.el ends here
