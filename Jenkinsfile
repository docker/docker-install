#!groovy

def verifyTargets = [
  'x86_64-verify-install-centos-7',
  'x86_64-verify-install-fedora-24',
  'x86_64-verify-install-fedora-25',
  'x86_64-verify-install-debian-wheezy',
  'x86_64-verify-install-debian-jessie',
  'x86_64-verify-install-debian-stretch',
  'x86_64-verify-install-ubuntu-trusty',
  'x86_64-verify-install-ubuntu-xenial',
  'x86_64-verify-install-ubuntu-zesty',
]

def armhfverifyTargets = [
  'armhf-verify-install-raspbian-jessie',
  'armhf-verify-install-debian-jessie',
  'armhf-verify-install-debian-stretch',
  'armhf-verify-install-ubuntu-trusty',
  'armhf-verify-install-ubuntu-xenial',
  'armhf-verify-install-ubuntu-zesty',
]

def s390xverifyTargets = [
  's390x-verify-install-ubuntu-xenial',
  's390x-verify-install-ubuntu-zesty',
]

def aarch64verifyTargets = [
  'aarch64-verify-install-ubuntu-xenial',
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

parallel(verifyJobs)
