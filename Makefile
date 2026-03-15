.PHONY: test clean

EMACS ?= emacs

# Detect straight.el build directory (Doom Emacs)
EMACS_VERSION := $(shell $(EMACS) --batch --eval '(princ emacs-version)' 2>/dev/null)
STRAIGHT_DIR ?= $(HOME)/.emacs.d/.local/straight/build-$(EMACS_VERSION)

# If cask is available, use it; otherwise use straight.el load paths
CASK := $(shell command -v cask 2>/dev/null)

ifdef CASK
  EMACS_CMD = $(CASK) exec $(EMACS)
  CASK_LOAD =
else ifneq ($(wildcard $(STRAIGHT_DIR)/buttercup),)
  EMACS_CMD = $(EMACS)
  CASK_LOAD = -L $(STRAIGHT_DIR)/buttercup \
	-L $(STRAIGHT_DIR)/org-roam \
	-L $(STRAIGHT_DIR)/emacsql \
	-L $(STRAIGHT_DIR)/emacsql-sqlite \
	-L $(STRAIGHT_DIR)/magit-section \
	-L $(STRAIGHT_DIR)/dash \
	-L $(STRAIGHT_DIR)/s \
	-L $(STRAIGHT_DIR)/f \
	-L $(STRAIGHT_DIR)/compat \
	-L $(STRAIGHT_DIR)/org \
	-L $(STRAIGHT_DIR)/transient \
	-L $(STRAIGHT_DIR)/with-editor
else
  $(error No test runner found. Install Cask or ensure straight.el packages are built)
endif

test:
	$(EMACS_CMD) --batch -L . -L test $(CASK_LOAD) \
		-l buttercup \
		-l test-helper \
		-l test-or-east \
		-f buttercup-run

clean:
	rm -rf .cask/
