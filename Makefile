APP := $(HOME)/Applications/Limits.app

.PHONY: install run uninstall clean

install:
	@./install.sh

run: install

uninstall:
	@./uninstall.sh

clean:
	@rm -rf build

