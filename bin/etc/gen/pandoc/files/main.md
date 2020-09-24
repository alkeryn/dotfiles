---
title: Template
author: Pierre-Louis Braun
date:  2020-02-01 - 2020-08-01
header-includes:
- |
    ```{=latex}
    \usepackage{graphicx,wrapfig,float}
    \usepackage{fancyvrb,newverbs,xcolor}
    \usepackage{framed,quoting}
    \graphicspath{{./img/}}

    \definecolor{Light}{HTML}{E7E7E7}

    % inline block
    \let\oldtexttt\texttt
    \renewcommand{\texttt}[1]{
	\colorbox{Light}{\oldtexttt{#1}}
    }

    \newenvironment{lcverbatim}
    {\SaveVerbatim{cverb}}
    {\endSaveVerbatim
	\flushleft\fboxrule=0pt\fboxsep=.5em
	    \colorbox{Light}{%
		\makebox[\dimexpr\linewidth-2\fboxsep][l]{\BUseVerbatim{cverb}}%
	    }
	\endflushleft
    }
    \counterwithin*{footnote}{page}
    ```

fontsize: 11pt

color-links: true
linkcolor: red
urlcolor: red
geometry: margin=1in

---

# Intro{#intro}

[//]: # intro

&nbsp;&nbsp;Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod
tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At
vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren,
no sea takimata sanctus est Lorem ipsum dolor sit amet.

# Sommaire :
1. **[Intro](#intro)**

\newpage

\begin{flushright}
Braun Pierre-Louis
\end{flushright}
