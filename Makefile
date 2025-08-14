.PHONY: all build clean run install

MESON_BUILD_DIR = build

all: build

build:
	rm -rf $(MESON_BUILD_DIR)
	meson setup $(MESON_BUILD_DIR)
	meson compile -C $(MESON_BUILD_DIR)
	@echo "Compiled $(MESON_BUILD_DIR) directory"

clean:
	rm -rf $(MESON_BUILD_DIR)
	@echo "Cleaned $(MESON_BUILD_DIR) directory"

run:
	$(MAKE) build
	@if [ -f $(MESON_BUILD_DIR)/ray_pulse ]; then \
		echo "Running ray_pulse..."; \
		./$(MESON_BUILD_DIR)/ray_pulse; \
	else \
		echo "Executable not found: $(MESON_BUILD_DIR)/ray_pulse"; \
		exit 1; \
	fi

install: build
	meson install -C $(MESON_BUILD_DIR)
