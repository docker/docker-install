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
  'armhf-verify-install-raspbian-stretch',
  'armhf-verify-install-debian-jessie',
  'armhf-verify-install-debian-stretch',
  // TEMPORARY: security.ubuntu.com is returning a 404 for trusty armhf, support may have ended
  // 'armhf-verify-install-ubuntu-trusty',
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
        def notifyDefaults = [context: t, description: 'Platform Test']
        githubNotify(notifyDefaults << [status: 'PENDING'])
        try {
          checkout scm
          channel = 'test'
          if ("${env.JOB_NAME}".endsWith('get.docker.com')) {
              channel='edge'
          }
          sh("make CHANNEL_TO_TEST=${channel} clean ${t}")
          archiveArtifacts '*-verify-install-*'
        } catch(err) {
          githubNotify(notifyDefaults << [status: 'FAILED'])
          throw err
        }
        githubNotify(notifyDefaults << [status: 'SUCCESS'])
      }
    }
  } ]
}

wrappedNode(label: 'aufs', cleanWorkspace: true) {
  stage('Shellcheck') {
    def notifyDefaults = [context: "shellcheck", description: 'Platform Test']
    githubNotify(notifyDefaults << [status: 'PENDING'])
    try {
      checkout scm
      sh('make shellcheck')
    } catch(err) {
      githubNotify(notifyDefaults << [status: 'FAILED'])
      throw err
    }
    githubNotify(notifyDefaults << [status: 'SUCCESS'])
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

parallel(verifyJobs)
