APP := $(HOME)/Applications/AI CLI Limits.app

.PHONY: install run uninstall clean test

install:
	@./install.sh

run: install

uninstall:
	@./uninstall.sh

clean:
	@rm -rf build

test:
	@./test.sh
