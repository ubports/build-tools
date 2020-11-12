def call(Boolean isArchIndependent = false) {
  String stashFileList = '*.gz,*.bz2,*.xz,*.deb,*.ddeb,*.udeb,*.dsc,*.changes,*.buildinfo,lintian.txt'
  String archiveFileList = '*.gz,*.bz2,*.xz,*.deb,*.ddeb,*.udeb,*.dsc,*.changes,*.buildinfo'

  pipeline {
    agent none
    options {
      // Only 'Build source' stage requires checkout.
      skipDefaultCheckout()
    }
    stages {
      stage('Build source') {
        agent { label 'amd64' }
        steps {
          dir('source') {
            checkout scm
          }
          sh 'SKIP_MOVE=true /usr/bin/build-source.sh'
          stash(name: 'source', includes: stashFileList)
          cleanWs(cleanWhenAborted: true, cleanWhenFailure: true, cleanWhenNotBuilt: true, cleanWhenSuccess: true, cleanWhenUnstable: true, deleteDirs: true)
        }
      }
      stage('Build binaries') {
        parallel {
          stage('Build binary - armhf') {
            agent { label 'arm64' }
            when { expression { return !isArchIndependent } }
            steps {
              unstash 'source'
              sh 'architecture="armhf" build-binary.sh'
              stash(includes: stashFileList, name: 'build-armhf')
              cleanWs(cleanWhenAborted: true, cleanWhenFailure: true, cleanWhenNotBuilt: true, cleanWhenSuccess: true, cleanWhenUnstable: true, deleteDirs: true)
            }
          }
          stage('Build binary - arm64') {
            agent { label 'arm64' }
            when { expression { return !isArchIndependent } }
            steps {
              unstash 'source'
              sh 'architecture="arm64" build-binary.sh'
              stash(includes: stashFileList, name: 'build-arm64')
              cleanWs(cleanWhenAborted: true, cleanWhenFailure: true, cleanWhenNotBuilt: true, cleanWhenSuccess: true, cleanWhenUnstable: true, deleteDirs: true)
            }
          }
          stage('Build binary - amd64') {
            agent { label 'amd64' }
            // Always run; arch-independent packages are built here.
            steps {
              unstash 'source'
              sh 'architecture="amd64" build-binary.sh'
              stash(includes: stashFileList, name: 'build-amd64')
              cleanWs(cleanWhenAborted: true, cleanWhenFailure: true, cleanWhenNotBuilt: true, cleanWhenSuccess: true, cleanWhenUnstable: true, deleteDirs: true)
            }
          }
        }
      }
      stage('Results') {
        agent { label 'amd64' }
        steps {
          unstash 'build-amd64'
          // If statement can only be evaluated under a script stage.
          script {
            if (!isArchIndependent) {
              unstash 'build-arm64'
              unstash 'build-armhf'
            }
          }
          archiveArtifacts(artifacts: archiveFileList, fingerprint: true, onlyIfSuccessful: true)
          sh '''/usr/bin/build-repo.sh'''
        }
      }
      stage('Cleanup') {
        agent { label 'amd64' }
        steps {
          cleanWs(cleanWhenAborted: true, cleanWhenFailure: true, cleanWhenNotBuilt: true, cleanWhenSuccess: true, cleanWhenUnstable: true, deleteDirs: true)
        }
      }
    }
  }
}
