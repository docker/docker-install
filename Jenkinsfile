#!groovy

def VERSION="18.09"

pipeline {
    agent {
        label "linux&&x86_64"
    }

    stages {
        stage("shellcheck") {
            steps {
                sh "make shellcheck"
            }
        }
        // Test out that the script will work for distros / version pinning
        stage("Check distributions / version pinning") {
            // NOTE: These can all technically run on the same node since they
            // run in containers
            parallel {
                stage("Ubuntu 18.04") {
                    steps {
                        sh "TEST_IMAGE=ubuntu:18.04 make test"
                    }
                }
                stage("Ubuntu 18.04 / version pinning") {
                    steps {
                        sh "TEST_IMAGE=ubuntu:18.04 VERSION=${VERSION} make test"
                    }
                }
                stage("Centos 7") {
                    steps {
                        sh "TEST_IMAGE=centos:7 make test"
                    }
                }
                stage("Centos 7 / version pinning") {
                    steps {
                        sh "TEST_IMAGE=centos:7 VERSION=${VERSION} make test"
                    }
                }
            }
        }
        // TODO: add release step here to upload to S3
    }
}
