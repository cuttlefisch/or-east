;;; or-east-mode.el --- Org Roam Extended Attribute Stat Tracking -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2022-2026 Hayden Stanko
;;
;; Author: Hayden Stanko <hayden@cuttle.codes>
;; Maintainer: Hayden Stanko <hayden@cuttle.codes>
;; Created: December 28, 2022
;; Version: 0.1.0
;; Keywords: convenience org-roam
;; Homepage: https://github.com/cuttlefisch/or-east
;; Package-Requires: ((emacs "28.1"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; or-east-mode is a minor mode that automatically tracks usage statistics
;; on org-roam nodes.  It records three properties in the node's property
;; drawer: last-accessed, last-modified, and last-linked.  These update
;; transparently via org-roam hooks during normal usage.
;;
;;; Code:

(require 'org)
(require 'org-id)
(require 'ol)
(require 'org-element)
(require 'org-roam)

(defgroup or-east nil
  "Org Roam Extended Attribute Stat Tracking."
  :group 'org-roam
  :prefix "or-east-")

(defcustom or-east-node-stat-format-time-string "%D"
  "Time-string passed to `format-time-string' when setting buffer stat properties."
  :type 'string
  :group 'or-east)

(defun or-east-node-time-string-now (&optional format-string)
  "Return timestamp formatted timestring.
Optional FORMAT-STRING overrides `or-east-node-stat-format-time-string'."
  (format-time-string (or format-string or-east-node-stat-format-time-string)))

;; TODO: This needs to recurse into all relevant org elements
(defvar or-east--inhibit-save nil
  "Non-nil while or-east is saving, to prevent recursive hook triggers.")

(defun or-east--save-buffer ()
  "Save the current buffer without triggering or-east hooks recursively."
  (when (and (buffer-modified-p)
             (file-exists-p (buffer-file-name)))
    (let ((or-east--inhibit-save t)
          (after-save-hook (remq #'or-east-node-update-stats after-save-hook)))
      (save-buffer))))

(defun or-east-node-update-stats ()
  "Update the `last-modified' property upon change to `body-hash'."
  (interactive)
  (when (and (not or-east--inhibit-save)
             (org-roam-buffer-p))
    (save-excursion
      (let ((body-hash (or-east-node-body-hash))
            (prev-body-hash (car (org-property-values "hash")))
            (time-string (or-east-node-time-string-now)))
        (goto-char (point-min))
        (unless (and prev-body-hash (string-equal prev-body-hash body-hash))
          (org-set-property "hash" body-hash)
          (org-set-property "last-modified" time-string)))
      (or-east--save-buffer)))
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
  (let ((file-path (or file-path (buffer-file-name (buffer-base-buffer)))))
    (save-excursion
      (with-temp-buffer
        (let ((src-text (or-east-node-get-string-of-file (or file-path nil))))
          (insert (substring src-text (or (string-match "#+title" src-text) 0)))
          (buffer-hash))))))

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
        ;; Use an existing buffer that is already visiting the file
        (with-current-buffer node-file-buffer
          (goto-char (point-min))
          (org-set-property "last-linked" (or-east-node-time-string-now))
          (or-east--save-buffer)))
       (node
        ;; No buffers currently visiting file
        (let ((file-path (org-roam-node-file node)))
          (with-temp-file file-path
            (insert-file-contents file-path)
            (goto-char (point-min))
            (org-set-property "last-linked" (or-east-node-time-string-now))))))))
  nil)

;; REVIEW: this isn't used
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
  (when (and (not or-east--inhibit-save)
             (buffer-file-name)
             (file-exists-p (buffer-file-name)))
    (save-excursion
      (goto-char (point-min))
      (org-set-property "last-accessed" (or-east-node-time-string-now))
      (or-east--save-buffer)))
  nil)

(defun or-east-node-handle-modified-time-tracking-h ()
  "Setup the current buffer to update the node-stats after saving the current file."
  (add-hook 'after-save-hook #'or-east-node-update-stats nil t))

;;;###autoload
(define-minor-mode or-east-mode
  "Minor mode to track usage statistics on org-roam nodes.
Automatically records last-accessed, last-modified, and last-linked
timestamps in each node's property drawer."
  :group 'or-east
  :global nil
  :init-value nil
  (let ((enabled or-east-mode))
    (cond
     (enabled
      (add-hook 'org-roam-find-file-hook #'or-east-node-update-access-time-by-id)
      (add-hook 'org-roam-find-file-hook #'or-east-node-handle-modified-time-tracking-h)
      (add-hook 'org-roam-post-node-insert-hook #'or-east-node-update-link-time-by-id))
     (t
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

;;; Activity scoring — for search prioritization

(defcustom or-east-activity-weights
  '((last-accessed . 1.0)
    (last-modified . 2.0)
    (last-linked   . 0.5))
  "Weights for computing node activity scores.
Each entry maps a tracked property to a numeric weight.  Higher
weight means that property contributes more to the final score.

Default rationale:
  - `last-modified' (2.0): recently edited nodes are most likely
    to be actively relevant right now.
  - `last-accessed' (1.0): recently opened nodes are familiar and
    easy to navigate back to.
  - `last-linked'   (0.5): recently linked nodes are contextually
    related but may not need direct revisiting.

Set a weight to 0.0 to ignore that property entirely.
Add custom property names if you extend or-east with new trackers."
  :type '(alist :key-type symbol :value-type number)
  :group 'or-east)

(defcustom or-east-activity-decay-rate 0.01
  "Controls how quickly activity scores decay over time.
The score for each property is computed as:
  weight * (1 / (1 + decay-rate * age-in-days))

With the default of 0.01:
  - A node accessed today scores 1.0
  - A node accessed 7 days ago scores ~0.93
  - A node accessed 30 days ago scores ~0.77
  - A node accessed 100 days ago scores ~0.50
  - A node accessed 365 days ago scores ~0.21

Lower values (e.g. 0.005) produce a flatter curve where older
nodes remain competitive longer.  Higher values (e.g. 0.05)
aggressively favor recent activity."
  :type 'number
  :group 'or-east)

(defun or-east--parse-date (date-str)
  "Parse DATE-STR in MM/DD/YY format to days since epoch, or nil if invalid."
  (when (and date-str
             (not (string-equal date-str "00/00/00"))
             (string-match "\\`\\([0-9]+\\)/\\([0-9]+\\)/\\([0-9]+\\)\\'" date-str))
    (let* ((month (string-to-number (match-string 1 date-str)))
           (day   (string-to-number (match-string 2 date-str)))
           (year  (+ 2000 (string-to-number (match-string 3 date-str))))
           (time  (encode-time 0 0 0 day month year)))
      (floor (float-time time) 86400))))

(defun or-east-node-activity-score (node)
  "Compute a weighted activity score for an org-roam NODE.
Returns a numeric score where higher means more recently/actively used.
The score is a weighted sum of days-since-epoch for each tracked property."
  (let ((props (org-roam-node-properties node))
        (today (floor (float-time) 86400))
        (score 0.0))
    (dolist (entry or-east-activity-weights score)
      (let* ((key    (upcase (symbol-name (car entry))))
             (weight (cdr entry))
             (val    (cdr (assoc key props)))
             (days   (or-east--parse-date val)))
        (when days
          (let ((age (max 0 (- today days))))
            (setq score (+ score (* weight (/ 1.0 (1+ (* or-east-activity-decay-rate age))))))))))))

(defun or-east-node-sort-by-activity (completion-a completion-b)
  "Comparison function: sort more active nodes first.
COMPLETION-A and COMPLETION-B are cons cells of (display-string . node)
as produced by `org-roam-node-read--completions'.
For use as `org-roam-node-default-sort' (via naming convention) or
as a SORT-FN argument to `org-roam-node-read'."
  (let ((node-a (cdr completion-a))
        (node-b (cdr completion-b)))
    (> (or-east-node-activity-score node-a)
       (or-east-node-activity-score node-b))))

;; Register with org-roam's naming convention so that setting
;; (setq org-roam-node-default-sort 'activity) just works.
(defalias 'org-roam-node-read-sort-by-activity #'or-east-node-sort-by-activity)

(provide 'or-east-mode)
;;; or-east-mode.el ends here
