
add_plenary:
	mkdir -p tests/site/pack/deps/start/
	ln -s ~/.local/share/YOUR-LAZY/lazy/telescope.nvim tests/site/pack/deps/start/telescope.nvim
	ln -s ~/.local/share/YOUR-LAZY/lazy/plenary.nvim tests/site/pack/deps/start/plenary.nvim

run_tests_headless:
	nvim --headless --noplugin -u run_tests.vim


