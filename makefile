lua := lua
dir := posts/
template := template.esbet

sources := $(wildcard $(dir)*/index.md)

all: $(sources:%.md=%.html)

$(dir)%.html: $(dir)%.md $(template)
	@echo COMPILING $<
	@$(lua) esbeg.lua $< $@ $(template)
