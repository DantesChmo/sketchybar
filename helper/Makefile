# Сборка единого event-provider для sketchybar.
#   make        — собрать бинарник sketchybar_metrics
#   make clean  — удалить бинарник

BIN      = sketchybar_metrics
SRC      = provider.c mach.c
CFLAGS   = -std=c99 -O2 -Wall -Wno-deprecated-declarations
FRAMEWORKS = -framework CoreFoundation -framework IOKit -framework Carbon

$(BIN): $(SRC) mach.h
	clang $(CFLAGS) $(SRC) -o $(BIN) $(FRAMEWORKS)

clean:
	rm -f $(BIN)

.PHONY: clean
