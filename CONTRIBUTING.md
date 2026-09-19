# Publicar uma versão

- Tag publicada nunca é movida nem apagada. Qualquer mudança, por menor que seja, vira versão nova
  (`v0.31.1`, `v0.31.2`...).
- A tag deste repositório e a tag das imagens da plataforma têm sempre o mesmo número: o setup puxa
  as imagens `v$VERSAO`. Publique as imagens antes de marcar a tag daqui.
- Antes de marcar: `VERSAO` em `setup/lib/base.sh` e o padrão de `install.sh` com o número novo,
  `shellcheck` sem erro e as três simulações de `setup/testes/` com saída 0.
