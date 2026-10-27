#!/usr/bin/env groovy

library 'status-jenkins-lib@v1.10.3'

/* Windows packages are mingw cross builds (packages.x86_64-windows.*),
 * so this runs on the regular Linux x86_64 container agent. */
pipeline {
  agent {
    docker {
      label 'linuxcontainer'
      image 'harbor.status.im/infra/ci-build-containers:linux-base-1.0.2'
      args '--volume=/nix:/nix ' +
           '--volume=/etc/nix:/etc/nix '
    }
  }

  parameters {
    string(
      name: 'MODULES',
      description: 'Comma-separated submodule dir names to build (required, set by the combined job).',
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

  environment {
    PLATFORM = 'windows/x86_64'
    VARIANT  = 'windows-amd64'
    TARGET   = 'x86_64-windows'
  }

  stages {
    stage('Build .lgx') {
      steps {
        script {
          buildAllModules()
        }
      }
    }

    stage('Archive') {
      steps {
        archiveArtifacts(artifacts: 'pkg/*', allowEmptyArchive: false)
      }
    }
  }

  post {
    cleanup {
      cleanWs(disableDeferredWipeout: true)
      dir(env.WORKSPACE_TMP) { deleteDir() }
    }
  }
}

def buildAllModules() {
  sh 'mkdir -p pkg logs'
  def results = [:]
  for (String m in getModules()) {
    try {
      buildModule(m)
      results[m] = 0
    } catch (ex) {
      results[m] = 1
      echo "FAIL  ${m}: ${ex.message}"
    }
    echo "${results[m] == 0 ? 'OK  ' : 'FAIL'}  ${m}"
  }
  writeReport(results)

  def failed = results.findAll { it.value != 0 }.keySet()
  if (failed) {
    unstable("Failed modules on ${env.VARIANT}: ${failed.join(', ')}")
  }
  if (results.every { it.value != 0 }) {
    error("All modules failed on ${env.VARIANT}")
  }
}

def getModules() {
  /* No "empty = all" here: which modules target Windows is decided by
   * getModuleTargets() in the combined job. */
  if (!params.MODULES?.trim()) {
    error('MODULES is required for the Windows job')
  }
  return params.MODULES.split(',').collect { it.trim() }.findAll { it }
}

def buildModule(String module) {
  def out = nix.flake(
    "packages.${env.TARGET}.lgx-portable",
    [path: "./submodules/${module}", link: false]
  )
  sh """#!/usr/bin/env bash
    set -euo pipefail
    lgx=\$(find '${out}' -maxdepth 2 -name '*.lgx' | head -n1)
    [[ -n "\$lgx" ]] || { echo 'no .lgx in build output' >&2; exit 1; }
    cp "\$lgx" 'pkg/${module}__${env.VARIANT}.lgx'
    chmod u+w 'pkg/${module}__${env.VARIANT}.lgx'
  """
}

def writeReport(Map results) {
  writeFile(
    file: "pkg/report__${env.VARIANT}.txt",
    text: results.collect { m, c -> "${c == 0 ? 'OK' : 'FAIL'} ${m}" }.join('\n') + '\n'
  )
}
