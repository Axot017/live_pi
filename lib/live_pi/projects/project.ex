defmodule LivePi.Projects.Project do
  @moduledoc """
  Normalized project metadata for the workspace UI.
  """

  @enforce_keys [:id, :name, :path, :root]
  defstruct [:id, :name, :path, :root, :source, :clone_status]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          path: String.t(),
          root: String.t(),
          source: :existing | :cloned | :unknown | nil,
          clone_status: :ready | :cloning | :failed | nil
        }
end
