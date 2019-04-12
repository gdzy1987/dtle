OS := $(shell uname)
VERSION := $(shell sh -c 'git describe --always --tags')
BRANCH := $(shell sh -c 'git rev-parse --abbrev-ref HEAD')
COMMIT := $(shell sh -c 'git rev-parse --short HEAD')
DOCKER        := $(shell which docker)
DOCKER_IMAGE  := docker-registry:5000/actiontech/universe-compiler-udup:v3

PROJECT_NAME  = dtle
VERSION       = 9.9.9.9

ifdef GOBIN
PATH := $(GOBIN):$(PATH)
else
PATH := $(subst :,/bin:,$(GOPATH))/bin:$(PATH)
endif

GOFLAGS ?= $(GOFLAGS:)

# Standard Dtle build
default: build

# Windows build
windows: build-windows

# Only run the build (no dependency grabbing)
build:
	go build $(GOFLAGS) -o dist/dtle -ldflags \
		"-X main.Version=$(VERSION) -X main.GitCommit=$(COMMIT) -X main.GitBranch=$(BRANCH)" \
		./cmd/dtle/main.go

build-windows:
	GOOS=windows GOARCH=amd64 go build $(GOFLAGS) -o dist/dtle.exe -ldflags \
		"-X main.Version=$(VERSION) -X main.GitCommit=$(COMMIT) -X main.GitBranch=$(BRANCH)" \
		./cmd/dtle/main.go

build_with_coverage_report: build-coverage-report-tool coverage-report-pre-build build coverage-report-post-build

build-coverage-report-tool:
	go install github.com/actiontech/dtle/vendor/github.com/ikarishinjieva/golang-live-coverage-report/cmd/golang-live-coverage-report

coverage-report-pre-build:
	PATH=${GOPATH}/bin:$$PATH golang-live-coverage-report \
	    -pre-build -raw-code-build-dir ./coverage-report-raw-code -raw-code-deploy-dir ./coverage-report-raw-code \
	    -bootstrap-outfile ./cmd/dtle/coverage_report_bootstrap.go -bootstrap-package-name main \
	    ./agent ./api ./utils ./cmd/dtle/command ./internal ./internal/g  ./internal/logger ./internal/models  ./internal/server ./internal/server/scheduler ./internal/server/store ./internal/client/driver ./internal/client/driver/kafka3 ./internal/client/driver/mysql ./internal/client/driver/mysql/base ./internal/client/driver/mysql/binlog ./internal/client/driver/mysql/sql ./internal/client/driver/mysql/util ./internal/client/driver/mysql/sqle/g ./internal/client/driver/mysql/sqle/inspector

coverage-report-post-build:
	PATH=${GOPATH}/bin:$$PATH golang-live-coverage-report \
	    -post-build -raw-code-build-dir ./coverage-report-raw-code -bootstrap-outfile ./cmd/dtle/coverage_report_bootstrap.go \
	    ./agent ./api ./utils ./cmd/dtle/command  ./internal ./internal/g  ./internal/logger ./internal/models  ./internal/server ./internal/server/scheduler ./internal/server/store ./internal/client/driver ./internal/client/driver/kafka3 ./internal/client/driver/mysql ./internal/client/driver/mysql/base ./internal/client/driver/mysql/binlog ./internal/client/driver/mysql/sql ./internal/client/driver/mysql/util ./internal/client/driver/mysql/sqle/g ./internal/client/driver/mysql/sqle/inspector

TEMP_FILE = temp_parser_file
goyacc:
	go build -o dist/goyacc vendor/github.com/pingcap/parser/goyacc/main.go

prepare: goyacc
	dist/goyacc -o /dev/null -xegen $(TEMP_FILE) vendor/github.com/pingcap/parser/parser.y
	dist/goyacc -o vendor/github.com/pingcap/parser/parser.go -xe $(TEMP_FILE) vendor/github.com/pingcap/parser/parser.y 2>&1 | egrep "(shift|reduce)/reduce" | awk '{print} END {if (NR > 0) {print "Find conflict in parser.y. Please check y.output for more information."; system("rm -f $(TEMP_FILE)"); exit 1;}}'
	rm -f $(TEMP_FILE)
	rm -f y.output

ifeq ($(OS),Darwin)
		@/usr/bin/sed -i "" 's|//line.*||' vendor/github.com/pingcap/parser/parser.go
		@/usr/bin/sed -i "" 's/yyEofCode/yyEOFCode/' vendor/github.com/pingcap/parser/parser.go
else
		@sed -i -e 's|//line.*||' -e 's/yyEofCode/yyEOFCode/' vendor/github.com/pingcap/parser/parser.go
endif

	@awk 'BEGIN{print "// Code generated by goyacc"} {print $0}' vendor/github.com/pingcap/parser/parser.go > tmp_parser.go && mv tmp_parser.go vendor/github.com/pingcap/parser/parser.go;

# run package script
package:
	./scripts/build.py --package --version="$(VERSION)" --platform=linux --arch=amd64 --clean --no-get

# Run "short" unit tests
test-short: vet
	go test -short ./...

vet:
	go vet ./...

fmt:
	gofmt -s -w .

mtswatcher: helper/mtswatcher/mtswatcher.go
	go build -o dist/mtswatcher ./helper/mtswatcher/mtswatcher.go

docker_rpm:
	$(DOCKER) run -v $(shell pwd)/:/universe/src/github.com/actiontech/dtle --rm $(DOCKER_IMAGE) -c "cd /universe/src/github.com/actiontech/dtle; GOPATH=/universe make prepare package"

docker_rpm_with_coverage_report:
	$(DOCKER) run -v $(shell pwd)/:/universe/src/github.com/actiontech/dtle --rm $(DOCKER_IMAGE) -c "cd /universe/src/github.com/actiontech/dtle; GOPATH=/universe make prepare build-coverage-report-tool coverage-report-pre-build package coverage-report-post-build"

upload:
	curl -T $(shell pwd)/dist/*.rpm -u admin:ftpadmin ftp://release-ftpd/actiontech-${PROJECT_NAME}/qa/${VERSION}/${PROJECT_NAME}-${VERSION}-qa.x86_64.rpm
	curl -T $(shell pwd)/dist/*.rpm.md5 -u admin:ftpadmin ftp://release-ftpd/actiontech-${PROJECT_NAME}/qa/${VERSION}/${PROJECT_NAME}-${VERSION}-qa.x86_64.rpm.md5

upload_with_coverage_report:
	curl -T $(shell pwd)/dist/*.rpm -u admin:ftpadmin ftp://release-ftpd/actiontech-${PROJECT_NAME}/qa/${VERSION}/${PROJECT_NAME}-${VERSION}-qa.coverage.x86_64.rpm
	curl -T $(shell pwd)/dist/*.rpm.md5 -u admin:ftpadmin ftp://release-ftpd/actiontech-${PROJECT_NAME}/qa/${VERSION}/${PROJECT_NAME}-${VERSION}-qa.coverage.x86_64.rpm.md5

.PHONY: test-short vet fmt build default
