#!/usr/bin/env groovy

library 'status-jenkins-lib@v1.10.3'

/* Shared by both Linux jobs; the arch comes from the job path. */
ARCH    = env.JOB_NAME.contains('aarch64') ? 'aarch64' : 'x86_64'
VARIANT = ARCH == 'aarch64' ? 'linux-arm64' : 'linux-amd64'

pipeline {
  agent {
    docker {
      label ARCH == 'aarch64' ? 'linux-arm-container' : 'linuxcontainer'
      image 'harbor.status.im/infra/ci-build-containers:linux-base-1.0.2'
      args '--volume=/nix:/nix ' +
           '--volume=/etc/nix:/etc/nix '
    }
  }

  parameters {
    string(
      name: 'MODULES',
      description: 'Comma-separated submodule dir names to build. Empty = all.',
      defaultValue: params.MODULES ?: ''
    )
    string(
      name: 'BRANCH',
      description: 'Git branch to build.',
      defaultValue: 'main'
    )
  }

  options {
    timestamps()
    ansiColor('xterm')
    timeout(time: 120, unit: 'MINUTES')
    buildDiscarder(logRotator(
      numToKeepStr: '10',
      daysToKeepStr: '30',
      artifactNumToKeepStr: '3',
    ))
    disableConcurrentBuilds()
    copyArtifactPermission('/logos/logos-modules-release/*')
  }

  stages {
    stage('Build .lgx') {
      steps { script { buildModules('lgx-portable') } }
    }

    stage('Archive') {
      steps { archiveArtifacts(artifacts: 'pkg/*') }
    }
  }

  post {
    cleanup {
      cleanWs(disableDeferredWipeout: true)
      dir(env.WORKSPACE_TMP) { deleteDir() }
    }
  }
}

def buildModules(String attr) {
  def modules = params.MODULES?.tokenize(', ') ?:
    findFiles(glob: 'submodules/*/metadata.json').collect { it.path.tokenize('/')[1] }.sort()
  def failed = []

  sh 'mkdir -p pkg'
  modules.each { m ->
    try {
      def out = nix.flake(attr, [path: "./submodules/${m}", link: false])
      sh """
        lgx=\$(find '${out}' -maxdepth 2 -name '*.lgx' | head -n1)
        [ -n "\$lgx" ] || { echo 'no .lgx in build output' >&2; exit 1; }
        cp "\$lgx" 'pkg/${m}__${VARIANT}.lgx'
      """
      echo "OK    ${m}"
    } catch (ex) {
      failed << m
      echo "FAIL  ${m}: ${ex.message}"
    }
  }

  writeFile(
    file: "pkg/report__${VARIANT}.txt",
    text: modules.collect { "${it in failed ? 'FAIL' : 'OK'} ${it}" }.join('\n') + '\n'
  )
  if (failed == modules) { error("All modules failed on ${VARIANT}") }
  if (failed) { unstable("Failed modules on ${VARIANT}: ${failed.join(', ')}") }
}
