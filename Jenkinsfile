#!groovy

def verifyTargets = [
  'verify-install-centos-7',
  'verify-install-fedora-24',
  'verify-install-fedora-25',
  'verify-install-debian-wheezy',
  'verify-install-debian-jessie',
  'verify-install-debian-stretch',
  'verify-install-ubuntu-trusty',
  'verify-install-ubuntu-xenial',
  'verify-install-ubuntu-zesty',
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
        archiveArtifacts 'verify-install-*'
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
