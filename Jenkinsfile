#!groovy

def verifyTargets = [
  'x86_64-verify-install-centos-7',
  'x86_64-verify-install-fedora-29',
  'x86_64-verify-install-ubuntu-xenial',
  'x86_64-verify-install-ubuntu-bionic',
]

def armhfverifyTargets = [
  'armhf-verify-install-ubuntu-xenial',
  'armhf-verify-install-ubuntu-bionic',
]

def s390xverifyTargets = [
  's390x-verify-install-ubuntu-xenial',
  's390x-verify-install-ubuntu-bionic',
]

def aarch64verifyTargets = [
  'aarch64-verify-install-ubuntu-xenial',
  'aarch64-verify-install-ubuntu-bionic',
  'aarch64-verify-install-centos-7',
  'aarch64-verify-install-fedora-29',
]

def ppc64leverifyTargets = [
  'ppc64le-verify-install-ubuntu-xenial',
  'ppc64le-verify-install-ubuntu-bionic',
]

def genVerifyJob(String t, String label) {
  return [ "${t}" : { ->
    stage("${t}") {
      wrappedNode(label: label, cleanWorkspace: true) {
        checkout scm
        channel = 'test'
        if ("${env.JOB_NAME}".endsWith('get.docker.com')) {
            channel='edge'
        }
        sh("make CHANNEL_TO_TEST=${channel} clean ${t}")
        archiveArtifacts '*-verify-install-*'
      }
    }
  } ]
}

wrappedNode(label: 'aufs', cleanWorkspace: true) {
  stage('Shellcheck') {
    checkout scm
    sh('make shellcheck')
  }
}

def verifyJobs = [:]
for (t in verifyTargets) {
  verifyJobs << genVerifyJob(t, 'aufs')
}

for (t in armhfverifyTargets) {
  verifyJobs << genVerifyJob(t, 'armhf')
}

for (t in s390xverifyTargets) {
  verifyJobs << genVerifyJob(t, 's390x-ubuntu-1604')
}

for (t in aarch64verifyTargets) {
  verifyJobs << genVerifyJob(t, 'aarch64')
}

for (t in ppc64leverifyTargets) {
  verifyJobs << genVerifyJob(t, 'ppc64le-ubuntu-1604')
}

parallel(verifyJobs)
