net use Z: \\192.168.100.1\work jkl /user:alkeryn > $null
z:
if($args[0]) { cd $args[0] }
clangd $args[1..($args.length)]
