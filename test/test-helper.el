;;; test-helper.el --- Test helpers for or-east -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(require 'buttercup)

;; Stub org-roam before or-east-mode tries to (require 'org-roam).
;; This avoids pulling in emacsql-sqlite which needs Emacs 29+ built-in SQLite.
(defvar org-roam-directory (make-temp-file "or-east-test-roam" t))
(defvar org-roam-db-location (expand-file-name "org-roam.db" org-roam-directory))
(defvar org-roam-find-file-hook nil)
(defvar org-roam-post-node-insert-hook nil)
(defun org-roam-buffer-p (&rest _) nil)
(defun org-roam-node-from-id (&rest _) nil)
(defun org-roam-node-file (&rest _) nil)
(defun org-roam-node-from-title-or-alias (&rest _) nil)
(defun org-roam-node-id (&rest _) nil)
(provide 'org-roam)

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
