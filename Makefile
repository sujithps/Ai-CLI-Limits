APP := $(HOME)/Applications/AI CLI Limits.app

.PHONY: install run uninstall clean

install:
	@./install.sh

run: install

uninstall:
	@./uninstall.sh

clean:
	@rm -rf build

