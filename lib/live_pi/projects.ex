defmodule LivePi.Projects do
  @moduledoc false

  @type project :: %{
          id: String.t(),
          name: String.t(),
          branch: String.t(),
          status: String.t(),
          path: String.t()
        }

  def list do
    projects_root()
    |> File.ls()
    |> case do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(projects_root(), &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.sort_by(&String.downcase(Path.basename(&1)))
        |> Enum.map(&to_project/1)

      {:error, _reason} ->
        []
    end
  end

  def projects_root do
    Application.get_env(:live_pi, :projects_root, Path.expand("~/Projects"))
    |> Path.expand()
  end

  defp to_project(path) do
    name = Path.basename(path)

    %{
      id: slugify(path),
      name: name,
      branch: git_branch(path),
      status: project_status(path),
      path: path
    }
  end

  defp git_branch(path) do
    case System.cmd("git", ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"],
           stderr_to_stdout: true
         ) do
      {branch, 0} ->
        branch
        |> String.trim()
        |> case do
          "" -> "directory"
          value -> value
        end

      _ ->
        "directory"
    end
  end

  defp project_status(path) do
    cond do
      File.exists?(Path.join(path, ".git")) -> "active"
      true -> "idle"
    end
  end

  defp slugify(path) do
    path
    |> Path.relative_to(projects_root())
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> unique_id("project")
      value -> value
    end
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
