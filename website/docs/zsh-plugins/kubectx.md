---
title: kubectx
---

# kubectx

Tiny plugin — one function, `kubectx_prompt_info`, which echoes the active
kubectl context (`kubectl config current-context`) for use in your prompt.
Despite the name it does *not* bundle the `kubectx`/`kubens` binaries; it's
purely prompt awareness.

## Pro tips

- **Its whole point is prod-vs-lab safety.** Wire it into the prompt
  (`RPS1='$(kubectx_prompt_info)'` in `~/.zshrc`) and you can never fat-finger
  a `kubectl delete` into the wrong cluster without the prompt telling you
  first. For occasional k8s work, this beats memorizing which kubeconfig is
  live.
- **Rename scary contexts loudly** via the `kubectx_mapping` associative
  array: `kubectx_mapping[long-prod-cluster-name]="%{$fg[yellow]%}prod!%{$reset_color%}"`.
  Values accept zsh prompt-expansion sequences, so the production context can
  be yellow and screaming while the lab one is a quiet `lab`.
- It shows nothing when `kubectl` isn't installed or no context is set — zero
  prompt noise on machines that never touch k8s, so it's safe to leave enabled
  everywhere in the dotfiles.
- Pair with the kubectl plugin's `kccc` (print context) and `kcuc` (switch
  context) — this plugin displays, those act.
