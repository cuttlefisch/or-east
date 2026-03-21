;;; or-east-mode.el --- Org Roam Extended Attribute Stat Tracking -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2022-2026 Hayden Stanko
;;
;; Author: Hayden Stanko <hayden@cuttle.codes>
;; Maintainer: Hayden Stanko <hayden@cuttle.codes>
;; Created: December 28, 2022
;; Version: 0.2.0
;; Keywords: convenience org-roam
;; Homepage: https://github.com/cuttlefisch/or-east
;; Package-Requires: ((emacs "28.1"))
;;
;; This file is not part of GNU Emacs.
;;
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;;; Commentary:
;;
;; or-east-mode is a minor mode that automatically tracks usage statistics
;; on org-roam nodes.  It records three properties in each node's property
;; drawer, updated transparently via org-roam hooks during normal usage:
;;
;;   - `last-accessed' — set when a node is opened via `org-roam-find-file'.
;;     Attached to `org-roam-find-file-hook'.
;;
;;   - `last-modified' — set when the node body changes.  or-east computes
;;     a `buffer-hash' of the content from the #+title keyword onward and
;;     compares it to a stored "hash" property; the timestamp updates only
;;     when the hash differs.  Attached to a buffer-local `after-save-hook'
;;     installed by `or-east--setup-modified-tracking'.
;;
;;   - `last-linked' — set on the *target* node when another node inserts
;;     a link to it.  Attached to `org-roam-post-node-insert-hook'.
;;
;; Additionally, or-east provides an activity scoring system that computes
;; a weighted, time-decayed score from the three tracked properties.  This
;; score can drive `org-roam-node-find' sorting so that recently active
;; nodes appear first.  See `or-east-activity-weights' and
;; `or-east-activity-decay-rate' for configuration.
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

;;; Time formatting

(defcustom or-east-node-stat-format-time-string "%Y-%m-%d"
  "Time-string passed to `format-time-string' when setting buffer stat properties.
The default format produces ISO 8601 dates like \"2026-03-21\", which are
unambiguous and lexicographically sortable."
  :type 'string
  :group 'or-east)

(defun or-east-node-time-string-now (&optional format-string)
  "Return the current time as a formatted string.
Optional FORMAT-STRING overrides `or-east-node-stat-format-time-string'.
The default format produces ISO 8601 dates like \"2026-03-21\"."
  (format-time-string (or format-string or-east-node-stat-format-time-string)))

;;; Internal helpers

(defvar or-east--inhibit-save nil
  "Non-nil while or-east is saving, to prevent recursive hook triggers.
Bound to t inside `or-east--save-buffer' so that `or-east-node-update-stats'
and `or-east-node-update-access-time-by-id' skip their work when the save
they triggered fires `after-save-hook' again.")

(defun or-east--save-buffer ()
  "Save the current buffer without triggering or-east hooks recursively.
Temporarily binds `or-east--inhibit-save' to t and removes
`or-east-node-update-stats' from the local `after-save-hook' before
calling `save-buffer'.  This prevents the save from re-entering
stat-update logic."
  (when (and (buffer-modified-p)
             (file-exists-p (buffer-file-name)))
    (let ((or-east--inhibit-save t)
          (after-save-hook (remq #'or-east-node-update-stats after-save-hook)))
      (save-buffer))))

;;; Property updates

(defun or-east-node-update-stats ()
  "Update the hash and last-modified properties if the node body changed.
Computes a `buffer-hash' of the current file's body (from the #+title
keyword onward) and compares it to the stored \"hash\" property.  When
they differ, both \"hash\" and \"last-modified\" are set to current values
and the buffer is saved.  Intended for use on `after-save-hook'
\(buffer-local, installed by `or-east--setup-modified-tracking').
Does nothing when `or-east--inhibit-save' is non-nil or the buffer
is not an org-roam buffer."
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

;;; File utilities

(defun or-east-node-get-string-of-file (file-path)
  "Return the contents of the file at FILE-PATH as a string.
If FILE-PATH is nil or the file does not exist, return an empty string.
This is used by `or-east-node-body-hash' to read node files."
  (if (and file-path (file-exists-p file-path))
      (save-excursion
        (with-temp-buffer
          (insert-file-contents file-path)
          (buffer-string)))
    ""))

(defun or-east-node-body-hash (&optional file-path)
  "Compute a `buffer-hash' of the node body in FILE-PATH.
The \"body\" is defined as everything from the first #+title keyword to
the end of the file, so that property-drawer-only changes (like
timestamp updates) do not count as content modifications.  If no
#+title is found, the entire file content is hashed.
When FILE-PATH is nil, defaults to the file backing the current buffer."
  (let ((file-path (or file-path (buffer-file-name (buffer-base-buffer)))))
    (save-excursion
      (with-temp-buffer
        (let ((src-text (or-east-node-get-string-of-file file-path)))
          (insert (substring src-text (or (string-match "#+title" src-text) 0)))
          (buffer-hash))))))

;;; Hook handlers

(defun or-east-node-update-link-time-by-id (id &rest _)
  "Update the last-linked property on the org-roam node identified by ID.
ID may be a string (node ID) or an org-element link object; in the
latter case, point is moved to the element and the :path property is
extracted as the ID string.  If the target node's file is already
visited in a buffer, that buffer is reused; otherwise the file is
read into a temporary buffer and written back.  Intended for use on
`org-roam-post-node-insert-hook'."
  (save-excursion
    (unless (stringp id)
      (goto-char (org-element-property :begin id))
      (setq id (org-element-property :path id))))
  (save-excursion
    (let* ((node (org-roam-node-from-id id))
           (node-file-buffer (if node
                                 (get-file-buffer (org-roam-node-file node))
                               nil)))
      (cond
       (node-file-buffer
        (with-current-buffer node-file-buffer
          (goto-char (point-min))
          (org-set-property "last-linked" (or-east-node-time-string-now))
          (or-east--save-buffer)))
       (node
        (let ((file-path (org-roam-node-file node)))
          (with-temp-file file-path
            (insert-file-contents file-path)
            (goto-char (point-min))
            (org-set-property "last-linked" (or-east-node-time-string-now))))))))
  nil)

(defun or-east-node-update-access-time-by-id ()
  "Set the current buffer's last-accessed property to the current time.
Guards against recursive saves via `or-east--inhibit-save' and verifies
the buffer is backed by an existing file.  Intended for use on
`org-roam-find-file-hook'."
  (when (and (not or-east--inhibit-save)
             (buffer-file-name)
             (file-exists-p (buffer-file-name)))
    (save-excursion
      (goto-char (point-min))
      (org-set-property "last-accessed" (or-east-node-time-string-now))
      (or-east--save-buffer)))
  nil)

(defun or-east--setup-modified-tracking ()
  "Add `or-east-node-update-stats' to the buffer-local `after-save-hook'.
This causes body-change detection and last-modified updates to run
each time the current org-roam buffer is saved.  Intended for use on
`org-roam-find-file-hook'."
  (add-hook 'after-save-hook #'or-east-node-update-stats nil t))

;;; Minor mode

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
      (add-hook 'org-roam-find-file-hook #'or-east--setup-modified-tracking)
      (add-hook 'org-roam-post-node-insert-hook #'or-east-node-update-link-time-by-id))
     (t
      (remove-hook 'org-roam-find-file-hook #'or-east-node-update-access-time-by-id)
      (remove-hook 'org-roam-find-file-hook #'or-east--setup-modified-tracking)
      (remove-hook 'org-roam-post-node-insert-hook #'or-east-node-update-link-time-by-id)))))

;;;###autoload
(defun or-east-enable ()
  "Activate `or-east-mode'."
  (or-east-mode +1))

;;;###autoload
(defun or-east-disable ()
  "Deactivate `or-east-mode'."
  (or-east-mode -1))

;;;###autoload
(defun or-east-toggle ()
  "Toggle `or-east-mode' enabled/disabled."
  (or-east-mode 'toggle))

;;; Activity scoring

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
  "Parse DATE-STR to days since epoch, or nil if invalid.
Handles ISO 8601 dates (\"2026-03-21\"), US dates (\"03/21/26\"),
and other formats supported by `parse-time-string'."
  (when (and date-str
             (not (string-empty-p date-str))
             (not (string-equal date-str "00/00/00"))
             (not (string-equal date-str "0000-00-00")))
    (let (day month year)
      ;; Try MM/DD/YY first (legacy %D format, not handled by parse-time-string)
      (if (string-match "\\`\\([0-9]+\\)/\\([0-9]+\\)/\\([0-9]+\\)\\'" date-str)
          (setq month (string-to-number (match-string 1 date-str))
                day   (string-to-number (match-string 2 date-str))
                year  (string-to-number (match-string 3 date-str)))
        ;; Fall back to parse-time-string (handles ISO 8601 and others)
        (let ((parsed (parse-time-string date-str)))
          (setq day   (nth 3 parsed)
                month (nth 4 parsed)
                year  (nth 5 parsed))))
      (when (and day month year (> day 0) (> month 0) (> year 0))
        ;; Two-digit years: assume 2000s (matches old %D behavior)
        (when (< year 100)
          (setq year (+ 2000 year)))
        (let ((time (encode-time 0 0 0 day month year)))
          (floor (float-time time) 86400))))))

(defun or-east--zero-sentinel-p (date-str)
  "Return non-nil if DATE-STR is an all-zeros sentinel date.
Matches \"00/00/00\", \"0000-00-00\", \"00/00/0000\", etc."
  (and (stringp date-str)
       (string-match-p "\\`[0/-]*0[0/-]*\\'" date-str)
       (not (string-empty-p date-str))))

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

;;; Timestamp normalization

;;;###autoload
(defun or-east-normalize-timestamps ()
  "Rewrite all or-east timestamps to the current format.
Walks every .org file in `org-roam-directory' and normalizes
`last-accessed', `last-modified', and `last-linked' properties to
`or-east-node-stat-format-time-string' (default \"%Y-%m-%d\").
Reports the number of files updated when done."
  (interactive)
  (let ((files (directory-files-recursively org-roam-directory "\\.org\\'"))
        (props '("last-accessed" "last-modified" "last-linked"))
        (format-str or-east-node-stat-format-time-string)
        (updated-count 0))
    (dolist (file files)
      (let ((file-modified nil))
        (with-temp-buffer
          (insert-file-contents file)
          (org-mode)
          (goto-char (point-min))
          (dolist (prop props)
            (let* ((val (car (org-property-values prop)))
                   (days (when val (or-east--parse-date val))))
              (cond
               (days
                ;; Valid date — reformat to current format string
                (let ((new-val (format-time-string format-str
                                                   (seconds-to-time (* days 86400)))))
                  (unless (string-equal val new-val)
                    (goto-char (point-min))
                    (org-set-property prop new-val)
                    (setq file-modified t))))
               ((and val (or-east--zero-sentinel-p val))
                ;; Zero sentinel in non-ISO form — normalize to 0000-00-00
                (unless (string-equal val "0000-00-00")
                  (goto-char (point-min))
                  (org-set-property prop "0000-00-00")
                  (setq file-modified t))))))
          (when file-modified
            (write-region (point-min) (point-max) file)
            (cl-incf updated-count)))))
    (message "or-east: normalized timestamps in %d file%s"
             updated-count (if (= updated-count 1) "" "s"))))

;; Register with org-roam's naming convention so that setting
;; (setq org-roam-node-default-sort 'activity) just works.
(defalias 'org-roam-node-read-sort-by-activity #'or-east-node-sort-by-activity)

(provide 'or-east-mode)
;;; or-east-mode.el ends here
