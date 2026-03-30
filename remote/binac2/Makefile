# Created in January 2025 by Christoph Schäfer
# Last updated on September 02, 2025 by Christian Jetter
# Last tested on September 02, 2025 at BinAC cluster

#Compiler/Linker
CXX             := ${MPI_BIN_DIR}/mpic++
NVCC            := ${CUDA_BIN_DIR}/nvcc

#Directories
PREFIX          := ${HOME}/local
CUDADIR        := ${CUDA_PATH}
MPIDIR         := ${MPI_HOME}
HDF5DIR        := ${HDF5_HOME}
BOOSTDIR       := ${BOOST_HOME}

# List of environment variables that should be set for each environment
ENV_VARS := CXX NVCC PREFIX CUDADIR MPIDIR HDF5DIR BOOSTDIR GPU_ARCH
DIR_VARS := PREFIX CUDADIR MPIDIR HDF5DIR BOOSTDIR

#Target binary
TARGET         := miluphpc

#Directories
SRCDIR         := ./src
INCDIR         := ./include
BUILDDIR       := ./build
TARGETDIR      := ./bin
RESDIR         := ./resources
IDEASDIR       := ./ideas
TESTDIR        := ./test
DOCDIR         := ./doc
DOCUMENTSDIR   := ./documents
CONFIGDIR      := ./config


SRCEXT         := cpp
CUDASRCEXT     := cu
DEPEXT         := d
OBJEXT         := o

add_includes = $(if $1,-I$1)

#Flags, Libraries and Includes
CXXFLAGS       += -std=c++11 -w -I${PREFIX}/include -I${MPIDIR}/include -I${HDF5DIR}/include -I${BOOSTDIR}/include
#NVFLAGS        := --std=c++11 -x cu -c -allow-unsupported-compiler -dc -w -Xcompiler "-pthread" -Wno-deprecated-gpu-targets -O3 -L -L${PREFIX}/lib -lboost_filesystem -lboost_system -lhdf5
NVFLAGS        := --std=c++11 -x cu -c -dc -w -Xcompiler "-pthread" -Wno-deprecated-gpu-targets -O3 -I${PREFIX}/include -I${MPIDIR}/include -I${HDF5DIR}/include -I${BOOSTDIR}/include
LFLAGS         += -lm -L$(CUDADIR)/lib64 -lcudart -lpthread -lconfig -L${PREFIX}/lib -L${MPIDIR}/lib -L${BOOSTDIR}/lib -L${HDF5DIR}/lib -lboost_atomic -lboost_serialization  -lmpi -lhdf5 -lboost_filesystem -lboost_system -lboost_mpi
GPU_ARCH       := -arch=sm_80
CUDALFLAGS     := -dlink
CUDALINKOBJ    := cuLink.o #needed?
LINKFLAGS      := -Wno-deprecated-gpu-targets
LIB            :=
INC            := -I$(INCDIR) -I$(CUDADIR)/include -I${PREFIX}/include -I${MPIDIR}/include -I${HDF5DIR}/include -I${BOOSTDIR}/include
INCDEP         := -I$(INCDIR)
MAKEFLAGS      += --no-print-directory


#Source and Object files
SOURCES        := $(shell find $(SRCDIR) -type f -name "*.$(SRCEXT)")
CUDA_SOURCES   := $(shell find $(SRCDIR) -type f -name "*.$(CUDASRCEXT)")
OBJECTS        := $(patsubst $(SRCDIR)/%,$(BUILDDIR)/%,$(SOURCES:.$(SRCEXT)=.$(OBJEXT)))
CUDA_OBJECTS   := $(patsubst $(SRCDIR)/%,$(BUILDDIR)/%,$(CUDA_SOURCES:.$(CUDASRCEXT)=.$(OBJEXT)))

#Documentation (Doxygen)
DOXY           := /usr/local/Cellar/doxygen/1.8.20/bin/doxygen
DOXYFILE       := $(DOCDIR)/Doxyfile

#default make (all)
all:
	@$(MAKE) precheck
	@echo "Compile ..."
	@$(MAKE) tester
	@$(MAKE) ideas
	@$(MAKE) $(TARGET)

precheck:
	@$(MAKE) list
	@echo "Check ..."
	@$(MAKE) checks

# Display all important environment variables with their current values
list:
	@echo "Current environment variables (please adjust as needed):"
	@$(foreach var,$(ENV_VARS), echo "  $(var) = '$($(var))'";)

checks: check_para check_vars check_dirs
	@true

check_para:
	@true
	@if [ ! -f ${INCDIR}/parameter.h ]; then \
		echo "  parameter.h is missing – copying template from ${CONFIGDIR}/"; \
		cp ${CONFIGDIR}/parameter.h ${INCDIR}/parameter.h; \
	else \
		echo "  ${INCDIR}/parameter.h is present."; \
	fi


# Check for empty variables and show an error if any are not set
check_vars:
	@true
	$(foreach var,$(ENV_VARS), \
		$(if $(strip $($(var))),, \
		$(error ERROR: Variable '$(var)' is empty. Please set it!)) )

# Check if include/ and lib/ directories exist for directory variables
check_dirs:
	@true
	$(foreach var,$(DIR_VARS), \
		$(if $(wildcard $($(var))/include),, \
			$(error ERROR: Directory '$($(var))/include' does not exist!)) \
		$(if $(wildcard $($(var))/lib*),, \
			$(error ERROR: Directory '$($(var))/lib' does not exist!)) )

single-precision: CXXFLAGS += -DSINGLE_PRECISION
single-precision: NVFLAGS += -DSINGLE_PRECISION
single-precision: all

debug: CXXFLAGS += -g
debug: NVFLAGS  += -g -G
debug: tester ideas $(TARGET)

#make regarding source files
sources: resources $(TARGET)

#remake
remake: cleaner all

#copy Resources from Resources Directory to Target Directory
resources: directories
	@cp -r $(RESDIR)/ $(TARGETDIR)/

#make directories
directories:
	@mkdir -p $(RESDIR)
	@mkdir -p $(TARGETDIR)
	@mkdir -p $(BUILDDIR)

#clean objects
clean:
	@$(RM) -rf $(BUILDDIR)

#clean objects and binaries
cleaner: clean
	@$(RM) -rf $(TARGETDIR)

#Pull in dependency info for *existing* .o files
-include $(OBJECTS:.$(OBJEXT)=.$(DEPEXT)) #$(INCDIR)/matplotlibcpp.h

#link
$(TARGET): $(OBJECTS) $(CUDA_OBJECTS)
	@echo "Linking ..."
	@$(NVCC) $(GPU_ARCH) $(LINKFLAGS) $(INC) -o $(TARGETDIR)/$(TARGET) $^ $(LIB) $(LFLAGS)

#compile
$(BUILDDIR)/%.$(OBJEXT): $(SRCDIR)/%.$(SRCEXT)
	@echo "  compiling (C++) : " $(SRCDIR)/$*
	@mkdir -p $(dir $@)
	@$(CXX) $(CXXFLAGS) $(INC) -c -o $@ $< $(LIB)
	@$(CXX) $(CXXFLAGS) $(INC) $(INCDEP) -MM $(SRCDIR)/$*.$(SRCEXT) > $(BUILDDIR)/$*.$(DEPEXT)
	@cp -f $(BUILDDIR)/$*.$(DEPEXT) $(BUILDDIR)/$*.$(DEPEXT).tmp
	@sed -e 's|.*:|$(BUILDDIR)/$*.$(OBJEXT):|' < $(BUILDDIR)/$*.$(DEPEXT).tmp > $(BUILDDIR)/$*.$(DEPEXT)
	@sed -e 's/.*://' -e 's/\\$$//' < $(BUILDDIR)/$*.$(DEPEXT).tmp | fmt -1 | sed -e 's/^ *//' -e 's/$$/:/' >> $(BUILDDIR)/$*.$(DEPEXT)
	@rm -f $(BUILDDIR)/$*.$(DEPEXT).tmp

$(BUILDDIR)/%.$(OBJEXT): $(SRCDIR)/%.$(CUDASRCEXT)
	@echo "  compiling (CUDA): " $(SRCDIR)/$*
	@mkdir -p $(dir $@)
	@$(NVCC) $(GPU_ARCH) $(INC) $(NVFLAGS) -I$(CUDADIR) -c -o $@ $<
	@$(NVCC) $(GPU_ARCH) $(INC) $(NVFLAGS) -I$(CUDADIR) -MM $(SRCDIR)/$*.$(CUDASRCEXT) > $(BUILDDIR)/$*.$(DEPEXT)


#compile test files
tester: directories
ifneq ("$(wildcard $(TESTDIR)/*.$(SRCEXT))","")
	@echo "  compiling: " test/*
	@$(CXX) $(CXXFLAGS) test/*.cpp $(INC) $(LIB) -o bin/tester
else
	@echo "No $(SRCEXT)-files within $(TESTDIR)!"
endif

#compile idea files
ideas: directories
ifneq ("$(wildcard $(IDEASDIR)/*.$(SRCEXT) )","")
	@echo "  compiling: " ideas/*
	@$(CXX) $(CXXFLAGS) ideas/*.cpp $(INC) $(LIB) -o bin/ideas
else
	@echo "No $(SRCEXT)-files within $(IDEASDIR)!"
endif

#@echo FILE_PATTERNS     = "*.md" "*.h" "*.$(SRCEXT)" >> $(DOCDIR)/doxyfile.inc
doxyfile.inc: #Makefile
	@echo INPUT            = README.md . $(SRCDIR)/ $(INCDIR)/ $(DOCUMENTSDIR)/ > $(DOCDIR)/doxyfile.inc
	@echo OUTPUT_DIRECTORY = $(DOCDIR)/ >> $(DOCDIR)/doxyfile.inc

#@$(MAKE) -C $(DOCDIR)/latex/ &> $(DOCDIR)/latex/latex.log
doc: doxyfile.inc
	$(DOXY) $(DOXYFILE) &> $(DOCDIR)/doxygen.log
	@mkdir -p "./docs"
	cp -r "./doc/html/" "./docs/"

#Non-File Targets
.PHONY: all remake clean cleaner resources sources directories ideas tester doc precheck


