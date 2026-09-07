# Pipeline Klin. Chaque cible correspond a une etape du CLAUDE.md.
# Sur Windows sans make : `python tools/klin.py <cible>` fait la meme chose.

PYTHON ?= python

# Jeu actif. `make GAME=<slug> <cible>`, ou export KLIN_GAME=<slug>.
# Sans valeur, les outils prennent l'unique jeu du repo et refusent de
# deviner des qu'il y en a plusieurs.
GAME ?=
G := $(if $(GAME),--game $(GAME),)

.DEFAULT_GOAL := help
.PHONY: help install doctor fmt fmt-check lint build test \
        assets products publish publish-live analytics spec generate clean

help: ## Liste les cibles disponibles
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# --- Environnement --------------------------------------------------------

install: ## Installe la toolchain (rokit) et les dependances (wally)
	rokit install
	wally install

doctor: ## Verifie la cle Open Cloud et ses scopes (lecture seule)
	@$(PYTHON) tools/doctor.py

# --- Qualite --------------------------------------------------------------

fmt: ## Formate le Luau avec StyLua
	stylua games skills

fmt-check: ## Echoue si le formatage n'est pas a jour
	stylua --check games

lint: fmt-check ## StyLua + Selene
	selene games

# --- Build et tests -------------------------------------------------------

build: ## Construit build/<slug>.rbxl
	@$(PYTHON) tools/publish.py $(G) --dry-run

test: ## Publie une version Saved et y execute la suite de tests
	@$(PYTHON) tools/test.py $(G)

wheel: ## Regenere l'image de la roue depuis GameConfig
	@$(PYTHON) tools/gen_wheel.py $(G)

# --- Pipeline Open Cloud --------------------------------------------------

assets: ## Resout assets/manifest.json et injecte les IDs dans la config
	@$(PYTHON) tools/assets.py $(G)

products: ## Cree/met a jour les Developer Products et Game Passes
	@$(PYTHON) tools/products.py $(G)

publish: ## Envoie une version Saved (non live) sur la place
	@$(PYTHON) tools/publish.py $(G)

publish-live: ## Envoie une version Published (visible par les joueurs)
	@$(PYTHON) tools/publish.py $(G) --live

reset: ## Supprime une sauvegarde (ex: make reset USER=Asukyy). DEFINITIF.
	@$(PYTHON) tools/reset_profile.py $(G) --username $(USER)

analytics: ## Ecrit reports/$(SLUG).md (ex: make analytics SLUG=coin-clicker)
	@$(PYTHON) tools/analytics.py $(G) $(if $(SLUG),--slug $(SLUG),)

# --- Generation de jeu (pas encore implemente) ----------------------------

spec: ## Ecrit games/<slug>/spec.md depuis un prompt
	@echo "pas encore implemente - voir CLAUDE.md, etape 1"
	@exit 1

generate: ## Genere le code du jeu depuis la spec
	@echo "pas encore implemente - voir CLAUDE.md, etape 2"
	@exit 1

# --- Divers ---------------------------------------------------------------

clean: ## Supprime les artefacts de build
	rm -rf build sourcemap.json
