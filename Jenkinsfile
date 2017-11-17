#!groovy

def verifyTargets = [
  'x86_64-verify-install-centos-7',
  'x86_64-verify-install-fedora-25',
  'x86_64-verify-install-fedora-26',
  'x86_64-verify-install-fedora-27',
  'x86_64-verify-install-debian-wheezy',
  'x86_64-verify-install-debian-jessie',
  'x86_64-verify-install-debian-stretch',
  'x86_64-verify-install-debian-buster',
  'x86_64-verify-install-ubuntu-trusty',
  'x86_64-verify-install-ubuntu-xenial',
  'x86_64-verify-install-ubuntu-zesty',
  'x86_64-verify-install-ubuntu-artful',
]

def armhfverifyTargets = [
  'armhf-verify-install-raspbian-jessie',
  'armhf-verify-install-raspbian-stretch',
  'armhf-verify-install-debian-jessie',
  'armhf-verify-install-debian-stretch',
  'armhf-verify-install-debian-buster',
  // TEMPORARY: security.ubuntu.com is returning a 404 for trusty armhf, support may have ended
  // 'armhf-verify-install-ubuntu-trusty',
  'armhf-verify-install-ubuntu-xenial',
  'armhf-verify-install-ubuntu-zesty',
  'armhf-verify-install-ubuntu-artful',
]

def s390xverifyTargets = [
  's390x-verify-install-ubuntu-xenial',
  's390x-verify-install-ubuntu-zesty',
  's390x-verify-install-ubuntu-artful',
]

def aarch64verifyTargets = [
  'aarch64-verify-install-ubuntu-xenial',
]

def ppc64leverifyTargets = [
  'ppc64le-verify-install-ubuntu-xenial',
  'ppc64le-verify-install-ubuntu-zesty',
  'ppc64le-verify-install-ubuntu-artful',
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
  verifyJobs << genVerifyJob(t, 's390x')
}

for (t in aarch64verifyTargets) {
  verifyJobs << genVerifyJob(t, 'aarch64')
}

for (t in ppc64leverifyTargets) {
  verifyJobs << genVerifyJob(t, 'ppc64le')
}

parallel(verifyJobs)
