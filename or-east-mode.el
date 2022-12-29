;;; or-east-mode.el --- Description -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2022 Hayden Stanko
;;
;; Author: Hayden Stanko <hayden@cuttle.codes>
;; Maintainer: Hayden Stanko <hayden@cuttle.codes>
;; Created: December 28, 2022
;; Modified: December 28, 2022
;; Version: 0.0.1
;; Keywords: abbrev bib c calendar comm convenience data docs emulations extensions faces files frames games hardware help hypermedia i18n internal languages lisp local maint mail matching mouse multimedia news outlines processes terminals tex tools unix vc wp
;; Homepage: https://github.com/cuttlefisch/or-east-mode
;; Package-Requires: ((emacs "26.1") (dash "2.13") (org "9.4") (emacsql "3.0.0") (emacsql-sqlite "1.0.0") (magit-section "3.0.0"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:
(require 'dash)
(require 'cl-lib)
(require 'emacsql)
(require 'emacsql-sqlite)

(require 'org)
(require 'org-attach)                   ; To set `org-attach-id-dir'
(require 'org-id)
(require 'ol)
(require 'org-element)
(require 'org-capture)

(require 'org-roam)


(defcustom or-east-node-stat-format-time-string "%D"
  "Time-string passed to `format-time-string' when setting buffer stat properties."
  :type 'string
  :group 'org-roam)

(defun or-east-node-time-string-now ()
  "Return timestamp formatted timestring."
  (format-time-string or-east-node-stat-format-time-string))

(defun or-east-node-update-stats ()
  "Update the `last-modified' property upon change to `body-hash'."
  (interactive)
  (if (org-roam-buffer-p)
      (save-excursion
        (let ((body-hash (or-east-node-body-hash))
              (prev-body-hash (car (org-property-values "hash")))
              (time-string (or-east-node-time-string-now)))
          (goto-char (point-min))
          (unless (and prev-body-hash (string-equal prev-body-hash body-hash))
            (org-set-property "hash" body-hash)
            (org-set-property "last-modified" time-string)))
        (if (and (file-exists-p (buffer-file-name))
                 (org-roam-node-from-id (car (org-property-values "id"))))
            (save-buffer))))
  nil)
(defun or-east-node-get-string-of-file (file-path)
  "Return content of file at FILE-PATH as a string."
  (if (and file-path (file-exists-p file-path))
      (save-excursion
        (with-temp-buffer
          (insert-file-contents file-path)
          (buffer-string)))
    ""))

(defun or-east-node-body-hash (&optional file-path)
  "Compute the `buffer-hash' of FILE-PATH."
  (setq file-path (or file-path (buffer-file-name (buffer-base-buffer))))
  (save-excursion
    (with-temp-buffer
      (let ((src-text (or-east-node-get-string-of-file (or file-path nil))))
        (insert (substring src-text (cl-search "#+title" src-text)))
        (buffer-hash)))))


(defun or-east-node-update-link-time-by-id (id &rest _)
  "Visit org roam node at ID and update its last-linked property."
  (save-excursion
    (unless (eq 'string (type-of id))
      (goto-char (org-element-property :begin id))
      (setq id (org-element-property :path id))))
  (save-excursion
    (let* ((node (org-roam-node-from-id id))
           ;; Check if file already visited so we can reuse that buffer
           (node-file-buffer (if node
                                 (get-file-buffer (org-roam-node-file node))
                               nil)))
      (cond
       (node-file-buffer
        ;; Use an existing buffer is already visiting the file
        (with-current-buffer node-file-buffer
          (save-buffer)
          (goto-char (point-min))
          (org-set-property "last-linked" (or-east-node-time-string-now))
          (save-buffer (current-buffer))))
       (node
        ;; No buffers currently visiting file
        (let ((file-path (org-roam-node-file node)))
          (with-temp-file file-path
            (insert-file-contents file-path)
            (goto-char (point-min))
            (org-set-property "last-linked" (or-east-node-time-string-now))))))))
  nil)

(defun or-east-link-replace-at-point (&optional link)
  "Replace \"roam:\" LINK at point with an \"id:\" link."
  (save-excursion
    (save-match-data
      (let* ((link (or link (org-element-context)))
             (type (org-element-property :type link))
             (path (org-element-property :path link))
             (desc (and (org-element-property :contents-begin link)
                        (org-element-property :contents-end link)
                        (buffer-substring-no-properties
                         (org-element-property :contents-begin link)
                         (org-element-property :contents-end link))))
             node)
        (goto-char (org-element-property :begin link))
        (when (and (org-in-regexp org-link-any-re 1)
                   (string-equal type "roam")
                   (setq node (save-match-data (org-roam-node-from-title-or-alias path))))
          (progn
            (replace-match (org-link-make-string
                            (concat "id:" (org-roam-node-id node))
                            (or desc path)))
            (or-east-node-update-link-time-by-id (org-roam-node-id node))))))))

(defun or-east-node-update-access-time-by-id ()
  "Update current buffer's `last-accessed' property."
  (when (file-exists-p (buffer-file-name))
    (save-excursion
      (goto-char (point-min))
      (org-set-property "last-accessed" (or-east-node-time-string-now))
      (if (and (file-exists-p (buffer-file-name))
               (org-roam-node-from-id (car (org-property-values "id"))))
          (save-buffer))))
  nil)

(defun or-east-node-handle-modified-time-tracking-h ()
  "Setup the current buffer to update the node-stats after saving the current file."
  (add-hook 'after-save-hook #'or-east-node-update-stats nil t))

;;;###autoload
(defun or-east-mode-dummy ()
  "Placeholder to test project structure."
  (let ((enabled or-east-mode))
    (cond
     (enabled
      (message "OR-EAST-MODE on"))
     (t
      (message "or-east-mode off")))))


;;;###autoload
(define-minor-mode or-east-mode
  "Global minor mode to Enhance the Org Roam Stat Tracking experience."
  :group 'org-roam
  :global t
  :init-value nil
  (let ((enabled or-east-mode))
    (cond
     (enabled
      (message "Adding hook for or-east-mode")
      (add-hook 'org-roam-find-file-hook #'or-east-node-update-access-time-by-id)
      (add-hook 'org-roam-find-file-hook #'or-east-node-handle-modified-time-tracking-h)
      (add-hook 'org-roam-post-node-insert-hook #'or-east-node-update-link-time-by-id))
     (t
      (message "Removing hook for or-east-mode")
      (remove-hook 'org-roam-find-file-hook #'or-east-node-update-access-time-by-id)
      (remove-hook 'org-roam-find-file-hook #'or-east-node-handle-modified-time-tracking-h)
      (remove-hook 'org-roam-post-node-insert-hook #'or-east-node-update-link-time-by-id)))))

;;;###autoload
(defun or-east-enable ()
  "Activate `or-east-mode'."
  (or-east-mode +1))

(defun or-east-disable ()
  "Deactivate `or-east-mode'."
  (or-east-mode -1))

(defun or-east-toggle ()
  "Toggle `or-east-mode' enabled/disabled."
  (or-east-mode 'toggle))


(provide 'or-east-mode)  ; (use-package! or-east-mode)
                                        ;(or-east-mode)
;;; or-east-mode.el ends here
