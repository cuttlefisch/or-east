;;; test-helper.el --- Test helpers for or-east -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(require 'buttercup)

;; Prevent org-roam from initializing a real database
(defvar org-roam-directory (make-temp-file "or-east-test-roam" t))
(defvar org-roam-db-location (expand-file-name "org-roam.db" org-roam-directory))

;; Stub org-roam functions that or-east calls so we can load without a DB
(unless (fboundp 'org-roam-buffer-p)
  (defun org-roam-buffer-p (&rest _) nil))
(unless (fboundp 'org-roam-node-from-id)
  (defun org-roam-node-from-id (&rest _) nil))
(unless (fboundp 'org-roam-node-file)
  (defun org-roam-node-file (&rest _) nil))

(require 'or-east-mode)

;;; Fixtures

(defvar or-east-test-org-content
  ":PROPERTIES:
:ID:       test-node-001
:END:
#+title: Test Node

This is the body of the test node.
It has multiple lines of content."
  "Sample org content with property drawer for testing.")

;;; Macros

(defmacro with-or-east-test-file (content &rest body)
  "Create a temp org file with CONTENT, execute BODY in its directory.
The file is cleaned up afterward."
  (declare (indent 1) (debug t))
  `(let* ((temp-dir (make-temp-file "or-east-test" t))
          (temp-file (expand-file-name "test-node.org" temp-dir)))
     (unwind-protect
         (progn
           (with-temp-file temp-file
             (insert ,content))
           (let ((default-directory temp-dir))
             ,@body))
       (delete-directory temp-dir t))))

(provide 'test-helper)
;;; test-helper.el ends here
