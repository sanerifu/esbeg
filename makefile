lua := lua
converter := esbeg.lua
dir := posts/
template := $(dir)template.html
index_name := $(dir)post_index.js

sources := $(wildcard $(dir)*/index.md)
outputs := $(sources:%.md=%.html)
indices := $(sources:%.md=%.json)

all: $(index_name)

$(index_name): $(indices)
	@echo MERGING
	@echo "local args = {...} for i=1,#args do local file = io.open(args[i], 'r') args[i] = file:read('*a'):gsub('[' .. string.char(10, 13) .. ']', '') file:close() end io.write('const __INDEX__ = [' .. table.concat(args, ',') .. ']')" | $(lua) - $^ > $@

$(dir)%.json: $(dir)%.md $(template) $(converter)
	@echo COMPILING $<
	@$(lua) $(converter) $< $(patsubst %.md,%.html,$<) $(template) > $@
