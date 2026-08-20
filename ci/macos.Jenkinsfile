#!/usr/bin/env groovy

library 'status-jenkins-lib@v1.9.48'

pipeline {
  agent { label "macos && ${getArch()} && nix-2.24" }

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

  environment {
    PLATFORM = "macos/${getArch()}"
    VARIANT  = "darwin-arm64"
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
  if (params.MODULES?.trim()) {
    return params.MODULES.split(',').collect { it.trim() }.findAll { it }
  }
  return sh(
    script: "find submodules -mindepth 1 -maxdepth 1 -type d | xargs -n1 basename | sort",
    returnStdout: true
  ).trim().split('\n') as List
}

def buildModule(String module) {
  def out = nix.flake('lgx-portable', [path: "./submodules/${module}", link: false])
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

def getArch() {
  def tokens = Thread.currentThread().getName().split('/')
  for (def arch in ['x86_64', 'aarch64']) {
    if (tokens.contains(arch)) { return arch }
  }
}
