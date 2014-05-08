# $Id: Makefile,v 1.1 2008/08/02 00:44:18 mitsuhide Exp mitsuhide $

SCRIPT_NAME	= numplc.rb
S = $(shell rcsdiff $(SCRIPT_NAME) > /dev/null 2>&1)

#SCRIPT_REV = `grep \$Id: Makefile,v 1.1 2008/08/02 00:44:18 mitsuhide Exp mitsuhide $(SCRIPT_NAME) | ruby -e 'split(/\s/)'`
Q_DIR	= q
A_DIR	= a

Q_FILES:= $(wildcard $(Q_DIR)/*.txt)
A_FILES = $(subst $(Q_DIR), $(A_DIR), $(Q_FILES) )


test:	RCS/$(SCRIPT_NAME),v

RCS/$(SCRIPT_NAME),v:	$(SCRIPT_NAME)
	./$(SCRIPT_NAME) $(subst $(A_DIR), $(Q_DIR), $@) > $@_mod

result:	$(A_FILES)

$(A_FILES): $(SCRIPT_NAME)
	./$(SCRIPT_NAME) $(subst $(A_DIR), $(Q_DIR), $@) > $@

echo:
	@echo $S
	@echo $(SCRIPT_REV)
	@echo $(SCRIPT_NAME)
	@echo $(Q_FILES)
	@echo $(A_FILES)
#@echo $(patsubst $(Q_DIR),$(A_DIR),$(Q_FILES) )
