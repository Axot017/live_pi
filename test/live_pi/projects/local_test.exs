defmodule LivePi.Projects.LocalTest do
  use ExUnit.Case, async: false

  alias LivePi.Projects.Local

  setup do
    base_dir =
      Path.join(System.tmp_dir!(), "live-pi-projects-local-#{System.unique_integer([:positive])}")

    root_a = Path.join(base_dir, "root-a")
    root_b = Path.join(base_dir, "root-b")
    clone_root = Path.join(base_dir, "clones")

    File.mkdir_p!(root_a)
    File.mkdir_p!(root_b)
    File.mkdir_p!(clone_root)

    previous_roots = Application.get_env(:live_pi, :project_roots)
    previous_clone_root = Application.get_env(:live_pi, :managed_clone_root)

    Application.put_env(:live_pi, :project_roots, [root_a, root_b])
    Application.put_env(:live_pi, :managed_clone_root, clone_root)

    on_exit(fn ->
      if previous_roots == nil do
        Application.delete_env(:live_pi, :project_roots)
      else
        Application.put_env(:live_pi, :project_roots, previous_roots)
      end

      if previous_clone_root == nil do
        Application.delete_env(:live_pi, :managed_clone_root)
      else
        Application.put_env(:live_pi, :managed_clone_root, previous_clone_root)
      end

      File.rm_rf!(base_dir)
    end)

    {:ok, root_a: root_a, root_b: root_b, clone_root: clone_root}
  end

  test "browse/1 returns entries and parent path within configured roots", %{root_a: root_a} do
    apps_dir = Path.join(root_a, "apps")
    alpha_dir = Path.join(apps_dir, "alpha")
    beta_dir = Path.join(apps_dir, "beta")

    File.mkdir_p!(alpha_dir)
    File.mkdir_p!(beta_dir)

    assert {:ok, browse} = Local.browse(apps_dir)
    assert browse.current_path == Path.expand(apps_dir)
    assert browse.root_path == Path.expand(root_a)
    assert browse.parent_path == Path.expand(root_a)

    assert Enum.map(browse.entries, & &1.name) == ["alpha", "beta"]
    assert Enum.all?(browse.entries, &(&1.selectable? and &1.type == :directory))
  end

  test "browse/1 rejects paths outside configured roots", %{root_a: root_a} do
    outside_dir = Path.join(Path.dirname(root_a), "outside")
    File.mkdir_p!(outside_dir)

    assert {:error, :path_outside_roots} = Local.browse(outside_dir)
  end

  test "list_projects/0 returns direct child directories from all roots", %{
    root_a: root_a,
    root_b: root_b
  } do
    File.mkdir_p!(Path.join(root_a, "alpha"))
    File.mkdir_p!(Path.join(root_b, "beta"))
    File.write!(Path.join(root_b, "README.txt"), "not a directory")

    projects = Local.list_projects()

    assert Enum.map(projects, & &1.name) == ["alpha", "beta"]
    assert Enum.all?(projects, &(&1.clone_status == :ready and &1.source == :existing))
  end

  test "select_project/1 returns normalized project metadata", %{root_a: root_a} do
    project_dir = Path.join(root_a, "nested/project")
    File.mkdir_p!(project_dir)

    assert {:ok, project} = Local.select_project(project_dir)
    assert project.name == "project"
    assert project.path == Path.expand(project_dir)
    assert project.root == Path.expand(root_a)
    assert project.source == :existing
    assert project.clone_status == :ready
  end

  test "clone_project/2 clones into managed root using sanitized destination", %{
    clone_root: clone_root
  } do
    test_pid = self()

    runner = fn executable, args, options ->
      send(test_pid, {:clone_command, executable, args, options})
      destination = List.last(args)
      File.mkdir_p!(destination)
      {"cloned", 0}
    end

    assert {:ok, project} =
             Local.clone_project("https://github.com/example/my-app.git",
               name: "my app",
               cmd_runner: runner
             )

    assert_received {:clone_command, "git",
                     ["clone", "--", "https://github.com/example/my-app.git", destination],
                     options}

    assert destination == Path.join(clone_root, "my-app")
    assert options[:cd] == Path.expand(clone_root)
    assert options[:stderr_to_stdout]
    assert options[:timeout] == :infinity

    assert project.name == "my-app"
    assert project.path == Path.expand(destination)
    assert project.root == Path.expand(clone_root)
    assert project.source == :cloned
  end

  test "clone_project/2 rejects invalid urls" do
    assert {:error, :invalid_repo_url} = Local.clone_project("git@github.com:example/repo.git")
    assert {:error, :invalid_repo_url} = Local.clone_project("file:///tmp/repo.git")
    assert {:error, :invalid_repo_url} = Local.clone_project("https://")
  end

  test "clone_project/2 rejects duplicate destinations", %{clone_root: clone_root} do
    File.mkdir_p!(Path.join(clone_root, "taken"))

    assert {:error, :destination_exists} =
             Local.clone_project("https://github.com/example/taken.git")
  end

  test "clone_project/2 returns clone failure output", %{clone_root: clone_root} do
    runner = fn _executable, _args, _options ->
      {"fatal: auth failed", 128}
    end

    assert {:error, {:clone_failed, "fatal: auth failed"}} =
             Local.clone_project("https://github.com/example/private-repo.git",
               name: "private-repo",
               cmd_runner: runner
             )

    refute File.exists?(Path.join(clone_root, "private-repo"))
  end
end
