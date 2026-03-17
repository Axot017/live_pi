defmodule LivePi.Projects.Local do
  @moduledoc """
  Default filesystem-backed project service.

  Projects are constrained to configured server-side roots. Existing projects can
  be discovered and browsed from those roots, while new repositories can be
  cloned into the managed clone root.
  """

  @behaviour LivePi.Projects

  alias LivePi.Config
  alias LivePi.Projects.Project

  @type cmd_runner :: (String.t(), [String.t()], keyword() -> {String.t(), non_neg_integer()})

  @impl true
  def roots do
    Config.project_roots()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&normalize_root/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @impl true
  def list_projects do
    roots()
    |> Enum.flat_map(&projects_in_root/1)
    |> Enum.sort_by(&{&1.name, &1.path})
  end

  @impl true
  def browse(nil) do
    case roots() do
      [root | _] -> browse(root)
      [] -> {:error, :no_project_roots_configured}
    end
  end

  def browse(path) when is_binary(path) do
    with {:ok, normalized_path, root} <- normalize_existing_path(path),
         :ok <- ensure_directory(normalized_path) do
      entries =
        normalized_path
        |> directory_entries(root)
        |> Enum.sort_by(&{not &1.selectable?, String.downcase(&1.name), &1.path})

      {:ok,
       %{
         current_path: normalized_path,
         root_path: root,
         parent_path: parent_path(normalized_path, root),
         entries: entries
       }}
    end
  end

  @impl true
  def select_project(path) do
    with {:ok, normalized_path, root} <- normalize_existing_path(path),
         :ok <- ensure_directory(normalized_path) do
      {:ok, build_project(normalized_path, root, :existing)}
    end
  end

  @impl true
  def clone_project(repo_url, opts \\ []) do
    with :ok <- validate_repo_url(repo_url),
         {:ok, clone_root} <- managed_clone_root(),
         {:ok, destination} <- clone_destination(clone_root, repo_url, opts),
         :ok <- ensure_available_destination(destination),
         {:ok, project} <- run_clone(repo_url, destination, clone_root, opts) do
      {:ok, project}
    end
  end

  defp projects_in_root(root) do
    case File.ls(root) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(root, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.map(&normalize_existing_dir!/1)
        |> Enum.map(&build_project(&1, root, :existing))

      {:error, _reason} ->
        []
    end
  end

  defp directory_entries(path, root) do
    with {:ok, entries} <- File.ls(path) do
      entries
      |> Enum.map(&Path.join(path, &1))
      |> Enum.filter(&File.dir?/1)
      |> Enum.map(&normalize_existing_dir!/1)
      |> Enum.filter(&within_root?(&1, root))
      |> Enum.map(fn entry_path ->
        %{
          name: Path.basename(entry_path),
          path: entry_path,
          type: :directory,
          selectable?: true
        }
      end)
    else
      {:error, _reason} -> []
    end
  end

  defp managed_clone_root do
    case Config.managed_clone_root() do
      nil ->
        {:error, :managed_clone_root_not_configured}

      root ->
        File.mkdir_p!(root)
        {:ok, normalize_root(root)}
    end
  end

  defp clone_destination(clone_root, repo_url, opts) do
    name =
      opts
      |> Keyword.get(:name, repo_name(repo_url))
      |> sanitize_destination_name()

    if name == "" do
      {:error, :invalid_destination_name}
    else
      destination = Path.join(clone_root, name)

      if within_root?(Path.expand(destination), clone_root) do
        {:ok, destination}
      else
        {:error, :invalid_destination_path}
      end
    end
  end

  defp ensure_available_destination(destination) do
    if File.exists?(destination) do
      {:error, :destination_exists}
    else
      :ok
    end
  end

  defp run_clone(repo_url, destination, clone_root, opts) do
    runner = Keyword.get(opts, :cmd_runner, &System.cmd/3)
    executable = Keyword.get(opts, :git_executable, "git")

    {output, exit_code} =
      runner.(executable, ["clone", "--", repo_url, destination],
        stderr_to_stdout: true,
        cd: clone_root,
        timeout: :infinity
      )

    if exit_code == 0 do
      {:ok, build_project(normalize_existing_dir!(destination), clone_root, :cloned)}
    else
      {:error, {:clone_failed, String.trim(output)}}
    end
  end

  defp validate_repo_url(repo_url) do
    uri = URI.parse(repo_url)

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, :invalid_repo_url}

      is_nil(uri.host) or uri.host == "" ->
        {:error, :invalid_repo_url}

      String.trim(uri.path || "") in ["", "/"] ->
        {:error, :invalid_repo_url}

      true ->
        :ok
    end
  end

  defp repo_name(repo_url) do
    repo_url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.basename()
    |> String.replace_suffix(".git", "")
  end

  defp sanitize_destination_name(name) do
    name
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9._-]+/u, "-")
    |> String.trim("-.")
  end

  defp normalize_existing_path(path) do
    expanded_path = Path.expand(path)

    with :ok <- ensure_exists(expanded_path),
         {:ok, root} <- find_root_for_path(expanded_path) do
      {:ok, expanded_path, root}
    end
  end

  defp normalize_existing_dir!(path) do
    Path.expand(path)
  end

  defp normalize_root(root) do
    normalize_existing_dir!(root)
  end

  defp ensure_exists(path) do
    if File.exists?(path), do: :ok, else: {:error, :path_not_found}
  end

  defp ensure_directory(path) do
    if File.dir?(path), do: :ok, else: {:error, :not_a_directory}
  end

  defp find_root_for_path(path) do
    case Enum.find(roots(), &within_root?(path, &1)) do
      nil -> {:error, :path_outside_roots}
      root -> {:ok, root}
    end
  end

  defp within_root?(path, root) do
    root_segments = Path.split(root)
    path_segments = Path.split(path)

    Enum.take(path_segments, length(root_segments)) == root_segments
  end

  defp parent_path(path, root) do
    if path == root do
      nil
    else
      candidate = Path.dirname(path)
      if within_root?(candidate, root), do: candidate, else: nil
    end
  end

  defp build_project(path, root, source) do
    %Project{
      id: project_id(path),
      name: Path.basename(path),
      path: path,
      root: root,
      source: source,
      clone_status: :ready
    }
  end

  defp project_id(path) do
    :sha256
    |> :crypto.hash(path)
    |> Base.url_encode64(padding: false)
  end
end
