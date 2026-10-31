# Quizy

An Emacs-native multiple-choice quiz for the shareable Org database in
[`data/quizy.org`](data/quizy.org).

## Run it

Emacs 27.1 or newer is required. Org Mode and the widget library are built
into Emacs; no packages need to be installed.

From this directory, open Emacs and evaluate:

```elisp
(add-to-list 'load-path "/path/to/quizy")
(require 'quizy)
(quizy)
```

Or load `quizy.el` with `M-x load-file`, then run `M-x quizy`.

Choose a category from the prompt, or choose **Случайный вопрос** to mix all
categories. Select an answer by clicking its button or pressing `1`–`4`.
Quizy marks the correct answer and tells you whether your choice was right.

| Key | Action |
| --- | --- |
| `1`–`4` | Select an answer |
| `n` | Show another question |
| `c` | Choose a category or random questions |
| `q` | Close the quiz |

Questions with an `IMAGE_LINK` show their image when the current Emacs frame
supports image display. The Org database is also easy to share or edit in
Org Mode. Override its location with:

```elisp
(setq quizy-database-file "/path/to/quizy.org")
```

## Database format

Each question is an Org heading with `CATEGORY`, `ANSWER1` through `ANSWER4`,
`CORRECT` (the 1-based answer number), and optionally `IMAGE_LINK` properties.
The loader checks that each question has four non-empty answers, a category,
and a valid correct-answer number before starting the quiz.

The quiz display keeps question selection, category filtering, answer
feedback, and rendering in separate functions so session features such as a
timer, energy, or question helpers can be added without changing the database
format.

## Tests

Run the built-in ERT tests with:

```sh
emacs -Q --batch -L . -L test -l test/quizy-test.el \
  -f ert-run-tests-batch-and-exit
```
