;;; quizy-test.el --- Tests for Quizy -*- lexical-binding: t; -*-

(require 'ert)
(require 'quizy)

(ert-deftest quizy-loads-the-shared-question-database ()
  (let ((questions (quizy-load-database)))
    (should (= (length questions) 941))
    (should (cl-every
             (lambda (question)
               (and (= (length (quizy-question-answers question)) 4)
                    (memq (quizy-question-correct question) '(1 2 3 4))))
             questions))))

(ert-deftest quizy-parses-category-and-answer-properties ()
  (let* ((questions (quizy-load-database))
         (question
          (seq-find
           (lambda (item)
             (equal (quizy-question-title item) "Какого цвета Пакман?"))
           questions)))
    (should question)
    (should (equal (quizy-question-category question) "Гик-культура"))
    (should (equal (quizy-question-correct question) 4))
    (should (equal (length (quizy-question-answers question)) 4))))

(ert-deftest quizy-image-links-resolve-from-the-shared-repository ()
  (let ((quizy--database-file quizy-database-file)
        (question
         (seq-find #'quizy-question-image (quizy-load-database))))
    (should question)
    (should (file-readable-p
             (quizy--image-path (quizy-question-image question))))))

(ert-deftest quizy-selects-only-questions-in-the-chosen-category ()
  (let ((questions
         (list (quizy-question-create
                :title "One" :category "A" :answers '("1" "2" "3" "4")
                :correct 1 :id "a")
               (quizy-question-create
                :title "Two" :category "B" :answers '("1" "2" "3" "4")
                :correct 1 :id "b"))))
    (with-temp-buffer
      (quizy-mode)
      (setq quizy--questions questions
            quizy--category "B")
      (cl-letf (((symbol-function 'quizy--render) #'ignore))
        (quizy--choose-question))
      (should (equal (quizy-question-category quizy--current-question) "B")))))

(ert-deftest quizy-shuffles-answers-and-tracks-the-correct-choice ()
  (let ((question (quizy-question-create
                   :title "Test question"
                   :category "Test"
                   :answers '("One" "Two" "Three" "Four")
                   :correct 2
                   :id "test")))
    (with-temp-buffer
      (quizy-mode)
      (setq quizy--questions (list question)
            quizy--category "Test")
      (cl-letf (((symbol-function 'quizy--shuffle)
                 (lambda (_sequence) '(4 3 2 1)))
                ((symbol-function 'quizy--render) #'ignore))
        (quizy--choose-question))
      (should (equal quizy--current-answers
                     '("Four" "Three" "Two" "One")))
      (should (= quizy--current-correct 3))
      (cl-letf (((symbol-function 'quizy--render) #'ignore))
        (quizy-answer 3))
      (should (= quizy--selected-answer quizy--current-correct)))))

(ert-deftest quizy-starts-with-four-selectable-answers ()
  (cl-letf (((symbol-function 'completing-read)
             (lambda (_prompt _collection &optional _predicate _require-match
                      _initial-input _hist default)
               default))
            ((symbol-function 'pop-to-buffer) #'ignore))
    (quizy)
    (with-current-buffer "*Quizy*"
      (should (derived-mode-p 'quizy-mode))
      (should (string-match-p "Категория: Случайный вопрос"
                              (buffer-string)))
      (dolist (number '(1 2 3 4))
        (should (string-match-p (format "\\[%d\\. " number)
                                (buffer-string))))))
  (when (get-buffer "*Quizy*")
    (kill-buffer "*Quizy*")))

(ert-deftest quizy-rejects-incomplete-question-entries ()
  (let ((file (make-temp-file "quizy-invalid-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "** Broken question\n:PROPERTIES:\n"
                    ":CATEGORY: Test\n:ANSWER1: One\n:CORRECT: 1\n"
                    ":END:\n"))
          (should-error (quizy-load-database file) :type 'user-error))
      (delete-file file))))

(ert-deftest quizy-shows-feedback-and-highlights-answer-buttons ()
  (let ((question (quizy-question-create
                   :title "Test question"
                   :category "Test"
                   :answers '("One" "Two" "Three" "Four")
                   :correct 2
                   :id "test")))
    (with-temp-buffer
      (quizy-mode)
      (setq quizy--questions (list question)
            quizy--database-file quizy-database-file
            quizy--category "Test"
            quizy--current-question question
            quizy--current-answers (quizy-question-answers question)
            quizy--current-correct (quizy-question-correct question))
      (quizy--render)
      (should (string-match-p "1\\. One" (buffer-string)))
      (should (string-match-p "4\\. Four" (buffer-string)))
      (quizy-answer 1)
      (should (= quizy--selected-answer 1))
      (should (string-match-p "Неверно\\. Правильный ответ: 2\\. Two"
                              (buffer-string)))
      (should (text-property-any (point-min) (point-max) 'face
                                 'quizy-correct-face))
      (should (text-property-any (point-min) (point-max) 'face
                                 'quizy-incorrect-face)))))

(provide 'quizy-test)

;;; quizy-test.el ends here
