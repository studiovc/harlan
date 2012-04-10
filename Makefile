
ALL_TEST_SRC = $(filter-out %~ %\# %.m, $(wildcard test/*))
XFAIL_TEST_SRC = $(shell grep -l xfail $(ALL_TEST_SRC))

RUN_TEST_SRC = $(filter-out $(XFAIL_TEST_SRC), $(ALL_TEST_SRC))

CXXFLAGS := -g -O2 gc/lib/libgc.a -Igc/include -Irt

# Set up the flags to handle OpenCL
ifeq ($(shell uname), Darwin)
CXXFLAGS := $(CXXFLAGS) -framework OpenCL
CXX := g++-4.2
else
ifeq ($(shell uname), Linux)
# This should work on 64-bit Gentoo with NVIDIA GPUs at least. YMMV.
CXXFLAGS := $(CXXFLAGS) -I/opt/cuda/include -lOpenCL -lrt
CXX := g++
ECHO_ESCAPE := "-e"
else
$(error Your operating system is not yet supported.)
endif
endif

HARLAN_SRC = \
	harlanc \
	$(wildcard harlan/*) \
	$(wildcard harlan/front/*) \
	$(wildcard harlan/middle/*) \
	$(wildcard harlan/back/*) \
	util/verify-grammar.ss \

# Invokes the harlan compiler. The first argument is the name of the
# source file, the second is the name of the output file.
HC = ./harlanc $(1) | $(CXX) -x c++ - -x none rt/libharlanrt.a $(CXXFLAGS) \
     -o $(2)

TEST_EXE_NAME = $(patsubst test/%, test.bin/%.bin, $(1))

TEST_OUT_NAME = $(patsubst test/%, test.bin/%.out, $(1))

COMPILE_TEST = $(call HC, $(1), $(call TEST_EXE_NAME, $(1)))

RUN_TEST = $(1)

.phony: check
check : test.bin gc/lib/libgc.a rt/libharlanrt.a update-submodules
	@./run-tests.scm
	@echo $(ECHO_ESCAPE) "\033[32mAll tests succeeded.\033[39m"

.phony: update-submodules
update-submodules: .gitmodules
	git submodule init
	git submodule update

.phony: force-check
force-check :
	rm -rf test.bin
	make -C . check

test.bin:
	mkdir -p test.bin

.phony: clean
clean:
	rm -rf test.bin *.dSYM gc
	make -C rt clean

test.bin/%.out : test.bin/%.bin
	@echo Running $<
	@$(call RUN_TEST, $(call TEST_EXE_NAME, $<)) > $@

.precious : $(call TEST_EXE_NAME, $(RUN_TEST_SRC))
test.bin/%.bin : test/% rt/libharlanrt.a $(HARLAN_SRC)
	@echo Compiling $<
	$(call COMPILE_TEST, $<)

gc/lib/libgc.a : update-submodules
	cd external/gc && \
	rm -f libatomic_ops && \
	ln -s ../libatomic_ops && \
	./configure --prefix=`pwd`/../../gc && \
	make -j4 && \
	make install

rt/libharlanrt.a : rt/*.h rt/*.cpp
	make -C rt

.phony: docs
docs: update-submodules
	make -C doc

#============================================================
# For JIT support we embed Chez Scheme in a static library:

# MACHINE = $(shell $(REGIMENTD)/apps/reuters/runtime/chez_machine_type_threaded)
MACHINE = $(shell ./util/chez_machine_type)
CHEZP = $(CHEZD)/boot/$(MACHINE)
STATICLIBS =
UNAME = $(shell uname -s)

LIBS = -lm -ldl -lncurses -lpthread 
ifeq ($(UNAME), Linux)
  LIBS+= -lrt
endif
ifeq ($(UNAME), Darwin)
  LIBS+= -liconv
endif


libharlanjit.a: harlan_jit.c harlan_jit.h
	@if [ -d "$(CHEZD)" ]; then echo; else echo "ERROR: CHEZD ($(CHEZD)) does not exist."; exit 1; fi
	gcc -c -fPIC -I $(CHEZP) harlan_jit.c -o harlan_jit.o
	ar rcs libharlanjit.a harlan_jit.o $(CHEZP)/kernel.o $(STATICLIBS)
	@echo;echo MADE SHARED LIBRARY; echo; echo

example_jit.exe: example_jit.c libharlanjit.a
	gcc -c -I $(CHEZP) example_jit.c
	gcc $(LIBS) libharlanjit.a example_jit.o -o example_jit.exe

#	$(CC) $(FLAGS) -c -I $(CHEZP) example_main.c 
#	$(CC) $(FLAGS) $(LIBS) example_main.o libwsq_runtime.a -o example_main.exe
