.PHONY: build clean install lint test

BINARY_NAME=openwrt-cli
GO=go
GOFLAGS=-ldflags="-s -w"

build:
	cd go && $(GO) build $(GOFLAGS) -o $(BINARY_NAME) ./cmd/...

clean:
	rm -f go/$(BINARY_NAME)

install: build
	install -m 755 go/$(BINARY_NAME) /usr/local/bin/

lint:
	cd go && $(GO) vet ./...

test:
	cd go && $(GO) test ./...

run: build
	./go/$(BINARY_NAME)

deploy-dns:
	./go/$(BINARY_NAME) deploy -i 192.168.1.1 -m dns

deploy-sqm:
	./go/$(BINARY_NAME) deploy -i 192.168.1.1 -m sqm

deploy-wifi:
	./go/$(BINARY_NAME) deploy -i 192.168.1.1 -m wifi

deploy-all:
	./go/$(BINARY_NAME) deploy -i 192.168.1.1

status:
	./go/$(BINARY_NAME) status -i 192.168.1.1

verify:
	./go/$(BINARY_NAME) verify -i 192.168.1.1

help:
	@echo "OpenWrt Config CLI"
	@echo ""
	@echo "Targets:"
	@echo "  build        Compila el binario"
	@echo "  clean        Elimina binarios"
	@echo "  install      Instala en /usr/local/bin"
	@echo "  lint         Ejecuta go vet"
	@echo "  test         Ejecuta tests"
	@echo "  run          Compila y ejecuta"
	@echo ""
	@echo "Comandos rápidos:"
	@echo "  make deploy-dns    Solo DNS + SafeSearch"
	@echo "  make deploy-sqm   Solo SQM CAKE"
	@echo "  make deploy-wifi  Solo WiFi"
	@echo "  make deploy-all   Todos los módulos"
	@echo "  make status       Ver estado"
	@echo "  make verify       Verificar config"