defmodule LivePi.ProjectsTest do
  use ExUnit.Case, async: false

  alias LivePi.Projects

  setup do
    original_root = Application.get_env(:live_pi, :projects_root)

    sandbox_dir =
      Path.join(System.tmp_dir!(), "live_pi_projects_test_#{System.unique_integer([:positive])}")

    projects_dir = Path.join(sandbox_dir, "projects")
    sources_dir = Path.join(sandbox_dir, "sources")

    File.mkdir_p!(projects_dir)
    File.mkdir_p!(sources_dir)

    Application.put_env(:live_pi, :projects_root, projects_dir)

    on_exit(fn ->
      if original_root do
        Application.put_env(:live_pi, :projects_root, original_root)
      else
        Application.delete_env(:live_pi, :projects_root)
      end

      File.rm_rf(sandbox_dir)
    end)

    %{projects_dir: projects_dir, sources_dir: sources_dir}
  end

  test "clone/1 clones repo into configured projects root", %{
    projects_dir: projects_dir,
    sources_dir: sources_dir
  } do
    source_repo = create_git_repo(sources_dir, "source-repo")

    assert {:ok, project} = Projects.clone(source_repo)
    assert project.name == "source-repo"
    assert project.path == Path.join(projects_dir, "source-repo")
    assert File.dir?(project.path)
    assert File.exists?(Path.join(project.path, ".git"))
  end

  test "clone/1 returns existing project without recloning", %{sources_dir: sources_dir} do
    source_repo = create_git_repo(sources_dir, "existing-repo-source")

    assert {:ok, project} = Projects.clone(source_repo)
    marker = Path.join(project.path, "marker.txt")
    File.write!(marker, "keep me")

    assert {:exists, existing_project} = Projects.clone(source_repo)
    assert existing_project.path == project.path
    assert File.read!(marker) == "keep me"
  end

  test "list/0 returns cloned directories", %{sources_dir: sources_dir} do
    source_repo = create_git_repo(sources_dir, "listed-repo-source")
    assert {:ok, cloned_project} = Projects.clone(source_repo)

    assert [%{name: "listed-repo-source", path: path}] = Projects.list()
    assert path == cloned_project.path
  end

  defp create_git_repo(root, name) do
    path = Path.join(root, "#{name}.git")
    File.mkdir_p!(path)

    run!("git", ["init", path])
    run!("git", ["-C", path, "config", "user.name", "Live Pi Test"])
    run!("git", ["-C", path, "config", "user.email", "test@example.com"])
    File.write!(Path.join(path, "README.md"), "# #{name}\n")
    run!("git", ["-C", path, "add", "README.md"])
    run!("git", ["-C", path, "commit", "-m", "init"])

    path
  end

  defp run!(command, args) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "command failed with status #{status}: #{output}"
    end
  end
end
