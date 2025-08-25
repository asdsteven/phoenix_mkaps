# Mkaps

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

```bash
sudo docker build . -t mkaps --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -f Dockerfile.dev
sudo docker run -it --rm -v "$PWD:/app" -v "$HOME/.terminfo:/terminfo" -p 4000:4000 -u $(id -u):$(id -g) -e TERMINFO=/terminfo -e TERM=eterm-color mkaps
```