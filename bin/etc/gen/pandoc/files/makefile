CC=pandoc
FROM=--from markdown+tex_math_single_backslash+raw_tex+raw_html
NAME=main
$(NAME): $(NAME).md
	$(CC) $(NAME).md $(FROM) -o $(NAME).pdf $(ARGS)
run:
	@setsid zathura $(NAME).pdf &
