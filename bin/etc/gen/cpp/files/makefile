CC=clang
CXX=clang++
CXXFLAGS=-std=c++17 -pthread -Ofast -I./src
DEPS = src/*.hpp
OBJ = $(shell find . -name "*.cpp" | sed 's/.cpp/.o/g')
OGL = -lSDL2 -lGL -lGLEW
export LDFLAGS
export OPTIONS
NAME = main

.PHONY: windows opengl clean vulkan gpu


%.o: %.cpp $(DEPS)
	$(CXX) -c -o $@ $< $(CXXFLAGS) $(OPTIONS)

$(NAME): $(OBJ)
	$(CXX) -o $@ $^ $(CXXFLAGS) $(LDFLAGS)

all:
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory $(NAME)

run: $(NAME)
	./$(NAME)

ifeq ($(OS),Windows_NT)
OGL := -lopengl32 -lglew32
clean:
	-del $(NAME) $(NAME).exe $(OBJ)
else
clean:
	-rm -f $(NAME) $(NAME).exe $(OBJ)
endif

windows: $(NAME)
opengl: $(NAME)
vulkan: $(NAME)
gpu: $(NAME)

ifneq (,$(findstring windows,$(MAKECMDGOALS)))
    CXX=x86_64-w64-mingw32-g++
    OGL := -lopengl32 -lglew32
endif

ifneq (,$(findstring opengl,$(MAKECMDGOALS)))
    OPTIONS+=-D "OGL"
    LDFLAGS+=$(OGL)
endif

ifneq (,$(findstring vulkan,$(MAKECMDGOALS)))
    OPTIONS+=-D "VK"
endif

ifneq (,$(findstring gpu,$(MAKECMDGOALS)))
    OPTIONS+=-D "GPU"
endif
