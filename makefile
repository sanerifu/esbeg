lua := $(shell command -v luajit 2>/dev/null || echo lua)
converter := esbeg.lua
site := ./

sources := $(sort $(wildcard $(site)posts/*/index.md))
to_be_compiled_sources := $(sources) $(site)index.md $(site)about/index.md
to_be_compiled := $(to_be_compiled_sources:%.md=%.html)
outputs := $(sources:%.md=%.html)
indices := $(sources:%.md=%.index)
feeds := $(sources:%.md=%.rss)

all: $(site)posts/index.html $(to_be_compiled)


$(site)templates/post.html: $(site)templates/menubar.html

$(site)posts/index.html: $(site)templates/posts.html $(outputs) 
	@echo MERGING
	@$(lua) $(converter) replace $(site)posts/index.html $(site)templates/posts.html $(indices)
	@$(lua) $(converter) replace $(site)rss.xml $(site)templates/rss.xml $(feeds)

%.html: %.md $(site)templates/post.html $(converter)
	@echo COMPILING $<
	@$(lua) $(converter) compile $(patsubst %.md,%.html,$<) $(patsubst %.md,%.index,$<) $(patsubst %.md,%.rss,$<) $< $(site)templates/post.html $(site)
