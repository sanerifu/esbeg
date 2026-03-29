lua := lua
dir := posts/
template := template.html
search_template := template_search.html

sources := $(wildcard $(dir)*/index.md)
outputs := $(sources:%.md=%.html)
indices := $(sources:%.md=%.json)

ifeq ($(OS),Windows_NT)
NULL_DEV := NUL
else
NULL_DEV := /dev/null
endif

all: index.json

index.json: $(indices)
	@echo MERGING
	@echo "local args = {...} for i=1,#args do local file = io.open(args[i], 'r') args[i] = file:read('*a'):gsub('[' .. string.char(10, 13) .. ']', '') file:close() end io.write('# [' .. table.concat(args, ',') .. ']')" | $(lua) - $^ > $@
	@cat $@ > index.md
	@$(lua) esbeg.lua index.md $(dir)index.html $(search_template) > $(NULL_DEV)
	@$(RM) index.json
	@$(RM) index.md

$(dir)%.json: $(dir)%.md $(template)
	@echo COMPILING $<
	@$(lua) esbeg.lua $< $(patsubst %.md,%.html,$<) $(template) > $@
