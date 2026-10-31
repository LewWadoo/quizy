;;; quizy.el --- Play questions from an Org database -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Eugene
;; Version: 0.1
;; Package-Requires: ((emacs "27.1"))
;; Keywords: games, org

;;; Commentary:

;; Run `M-x quizy' to choose a category and answer questions from
;; data/quizy.org.  The database uses Org headings with ANSWER1-4,
;; CORRECT, CATEGORY, and optional IMAGE_LINK properties.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-element)
(require 'seq)
(require 'subr-x)
(require 'widget)

(defgroup quizy nil
  "Answer questions from an Org Mode database."
  :group 'games)

(defcustom quizy-database-file
  (expand-file-name "data/quizy.org"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Path to the Org file containing quiz questions."
  :type 'file
  :group 'quizy)

(defface quizy-correct-face
  '((t (:inherit success :weight bold)))
  "Face used for the correct answer."
  :group 'quizy)

(defface quizy-incorrect-face
  '((t (:inherit error :weight bold)))
  "Face used for an incorrect selection."
  :group 'quizy)

(cl-defstruct (quizy-question (:constructor quizy-question-create))
  title category answers correct image id)

(defconst quizy--random-category "Случайный вопрос"
  "Display name for the unfiltered question choice.")

(defvar-local quizy--questions nil)
(defvar-local quizy--database-file nil)
(defvar-local quizy--category nil)
(defvar-local quizy--current-question nil)
(defvar-local quizy--current-answers nil)
(defvar-local quizy--current-correct nil)
(defvar-local quizy--selected-answer nil)
(defvar-local quizy--last-question-id nil)

(defun quizy--property-from-text (text property)
  "Return PROPERTY's value from an Org entry's property drawer in TEXT."
  (when (string-match
         (concat "^:" (regexp-quote property) ":[ \t]*\\(.*\\)$")
         text)
    (string-trim (match-string 1 text))))

(defun quizy-load-database (&optional file)
  "Return the questions in FILE, or `quizy-database-file' if omitted.
Question headings with an ANSWER1 property must have four nonempty
answers, a category, and a CORRECT value from 1 through 4."
  (let ((database (expand-file-name (or file quizy-database-file))))
    (unless (file-readable-p database)
      (user-error "Quiz database is not readable: %s" database))
    (with-temp-buffer
      (insert-file-contents database)
      (org-mode)
      (let (questions)
        (org-element-map (org-element-parse-buffer) 'headline
          (lambda (headline)
            (let* ((begin (org-element-property :begin headline))
                   (title-end
                    (save-excursion
                      (goto-char begin)
                      (forward-line 1)
                      (point)))
                   (entry-end
                    (save-excursion
                      (goto-char title-end)
                      (if (re-search-forward "^\\*+ " nil t)
                          (match-beginning 0)
                        (point-max))))
                   (entry-text (buffer-substring-no-properties
                                title-end entry-end))
                   (answer1 (quizy--property-from-text entry-text "ANSWER1")))
              (when answer1
                (let* ((title (org-element-property :raw-value headline))
                     (category (quizy--property-from-text
                                entry-text "CATEGORY"))
                     (answers
                      (mapcar (lambda (number)
                                (quizy--property-from-text
                                 entry-text (format "ANSWER%d" number)))
                              '(1 2 3 4)))
                     (correct (quizy--property-from-text
                               entry-text "CORRECT"))
                     (image (quizy--property-from-text
                             entry-text "IMAGE_LINK"))
                     (id (quizy--property-from-text entry-text "ID")))
                (unless (and (not (string-empty-p (or category "")))
                             (cl-every (lambda (answer)
                                         (not (string-empty-p
                                               (string-trim (or answer "")))))
                                       answers)
                             (member correct '("1" "2" "3" "4")))
                  (user-error "Invalid quiz entry at line %d: %s"
                              (line-number-at-pos begin) title))
                (push (quizy-question-create
                       :title title
                       :category (string-trim category)
                       :answers (mapcar #'string-trim answers)
                       :correct (string-to-number correct)
                       :image (unless (equal image "nil") image)
                       :id id)
                      questions))))))
        (nreverse questions)))))

(defun quizy--categories ()
  "Return sorted categories from the current question list."
  (delete-dups
   (sort (mapcar #'quizy-question-category quizy--questions) #'string<)))

(defun quizy--read-category ()
  "Prompt for a category or random questions."
  (completing-read "Категория: "
                   (cons quizy--random-category (quizy--categories))
                   nil t nil nil quizy--random-category))

(defun quizy--image-path (image)
  "Resolve IMAGE relative to the repository containing the database."
  (when (and image quizy--database-file)
    (let* ((database-directory
            (file-name-directory (expand-file-name quizy--database-file)))
           (repository-root
            (or (locate-dominating-file database-directory "images")
                database-directory)))
      (expand-file-name image repository-root))))

(defun quizy--shuffle (sequence)
  "Return a shuffled list containing the elements of SEQUENCE."
  (let ((items (vconcat sequence)))
    (cl-loop for index downfrom (1- (length items)) above 0
             for other = (random (1+ index))
             for value = (aref items index)
             do (aset items index (aref items other))
             (aset items other value))
    (append items nil)))

(defun quizy--render-answer (number answer)
  "Render answer NUMBER and ANSWER as a selectable widget."
  (let* ((selected quizy--selected-answer)
         (is-correct (= number quizy--current-correct))
         (face (when selected
                 (cond
                  (is-correct 'quizy-correct-face)
                  ((= number selected) 'quizy-incorrect-face))))
         (suffix (cond
                  ((and selected is-correct) " [верный ответ]")
                  ((and selected (= number selected)) " [ваш выбор]")
                  (t "")))
         (begin (point)))
    (widget-create
     'push-button
     :tag (format "%d. %s%s" number answer suffix)
     :button-face (or face 'widget-button)
     :notify (lambda (_widget &optional _event)
               (quizy-answer number)))
    (when face
      (put-text-property begin (point) 'face face))
    (widget-insert "\n")
    nil))

(defun quizy--render ()
  "Render the current question and its answer controls."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize "Quizy\n" 'face '(:height 1.5 :weight bold)))
    (insert (format "Категория: %s\n\n"
                    (if (equal quizy--category quizy--random-category)
                        quizy--random-category
                      quizy--category)))
    (insert (propertize (quizy-question-title quizy--current-question)
                        'face '(:height 1.3 :weight bold)))
    (insert "\n\n")
    (let* ((image (quizy-question-image quizy--current-question))
           (image-path (quizy--image-path image)))
      (when (and image-path (file-readable-p image-path))
        (if (display-images-p)
            (progn
              (insert-image (create-image image-path))
              (insert "\n\n"))
          (insert (format "[Изображение: %s]\n\n" image)))))
    (dotimes (index 4)
      (quizy--render-answer (1+ index)
                            (nth index quizy--current-answers)))
    (when quizy--selected-answer
      (let* ((correct quizy--current-correct)
             (right (= quizy--selected-answer correct)))
        (insert "\n")
        (insert
         (propertize
          (if right
              "Правильно!"
            (format "Неверно. Правильный ответ: %d. %s"
                    correct
                    (nth (1- correct) quizy--current-answers)))
          'face (if right 'quizy-correct-face 'quizy-incorrect-face)))))
    (insert "\n\n[n] Следующий вопрос   [c] Категория   [q] Выход\n")
    (widget-setup)
    (goto-char (point-min))))

(defun quizy--choose-question ()
  "Choose and render a random question matching the selected category."
  (let* ((pool (if (equal quizy--category quizy--random-category)
                   quizy--questions
                 (seq-filter
                  (lambda (question)
                    (equal quizy--category
                           (quizy-question-category question)))
                  quizy--questions)))
         (without-repeat
          (seq-remove
           (lambda (question)
             (equal quizy--last-question-id (quizy-question-id question)))
           pool)))
    (unless pool
      (user-error "No questions found for category: %s" quizy--category))
    (let* ((question (seq-random-elt (or without-repeat pool)))
           (answer-order (quizy--shuffle '(1 2 3 4))))
      (setq quizy--current-question question
            quizy--current-answers
            (mapcar (lambda (number)
                      (nth (1- number) (quizy-question-answers question)))
                    answer-order)
            quizy--current-correct
            (1+ (cl-position (quizy-question-correct question)
                             answer-order))
            quizy--selected-answer nil
            quizy--last-question-id (quizy-question-id question)))
    (quizy--render)))

(defun quizy-next-question ()
  "Show another random question in the current category."
  (interactive)
  (unless quizy--questions
    (user-error "Start a quiz with M-x quizy first"))
  (quizy--choose-question))

(defun quizy-select-category ()
  "Choose a category or switch back to random questions."
  (interactive)
  (unless quizy--questions
    (user-error "Start a quiz with M-x quizy first"))
  (setq quizy--category (quizy--read-category)
        quizy--last-question-id nil)
  (quizy--choose-question))

(defun quizy-answer (number)
  "Select answer NUMBER and show whether it is correct."
  (interactive "nОтвет (1-4): ")
  (unless (and quizy--current-question (memq number '(1 2 3 4)))
    (user-error "Choose an answer from 1 to 4"))
  (unless quizy--selected-answer
    (setq quizy--selected-answer number)
    (quizy--render)))

(defun quizy-answer-1 ()
  "Select answer 1."
  (interactive)
  (quizy-answer 1))

(defun quizy-answer-2 ()
  "Select answer 2."
  (interactive)
  (quizy-answer 2))

(defun quizy-answer-3 ()
  "Select answer 3."
  (interactive)
  (quizy-answer 3))

(defun quizy-answer-4 ()
  "Select answer 4."
  (interactive)
  (quizy-answer 4))

(define-derived-mode quizy-mode special-mode "Quizy"
  "Major mode for answering questions from the Quizy Org database."
  (define-key quizy-mode-map (kbd "1") #'quizy-answer-1)
  (define-key quizy-mode-map (kbd "2") #'quizy-answer-2)
  (define-key quizy-mode-map (kbd "3") #'quizy-answer-3)
  (define-key quizy-mode-map (kbd "4") #'quizy-answer-4)
  (define-key quizy-mode-map (kbd "n") #'quizy-next-question)
  (define-key quizy-mode-map (kbd "c") #'quizy-select-category)
  (define-key quizy-mode-map (kbd "q") #'quit-window))

;;;###autoload
(defun quizy ()
  "Start a random quiz from `quizy-database-file'."
  (interactive)
  (let ((questions (quizy-load-database)))
    (unless questions
      (user-error "No questions found in %s" quizy-database-file))
    (let ((buffer (get-buffer-create "*Quizy*")))
      (with-current-buffer buffer
        (quizy-mode)
        (setq quizy--questions questions
              quizy--database-file (expand-file-name quizy-database-file)
              quizy--category (quizy--read-category)
              quizy--last-question-id nil)
        (quizy--choose-question))
      (pop-to-buffer buffer))))

(provide 'quizy)

;;; quizy.el ends here
