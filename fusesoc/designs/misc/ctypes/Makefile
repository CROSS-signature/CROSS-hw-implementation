TARGET=libcross.so

.PHONY : clean

version=RSDP
category=CATEGORY_1
corner=SPEED

CFLAGS= -fPIC -g -I./inc -D${version} -D${category} -D${corner}
LDFLAGS= -shared

SOURCES = $(shell echo src/*.c)
HEADERS = $(shell echo inc/*.h)
OBJECTS=$(SOURCES:.c=.o)

all: clean $(TARGET)

clean:
	rm -f $(OBJECTS) $(TARGET)

$(TARGET) : $(OBJECTS)
	$(CC) $(CFLAGS) $(OBJECTS) -o $@ $(LDFLAGS)
