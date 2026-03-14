# NOTE: script from pipeline-sandbox repo.
import subprocess
import os

def render_model(model_path, output_dir="renders"):
    """
    Renders a 3D model using Blender by calling it as a subprocess.

    Args:
        model_path (str): The absolute path to the 3D model file.
        output_dir (str): The directory to save the rendered images to.
    """
    blender_script_path = os.path.abspath("auto_render.py")

    if not os.path.exists(model_path):
        print(f"Error: Model path does not exist: {model_path}")
        return

    # Ensure the output directory exists
    os.makedirs(output_dir, exist_ok=True)

    try:
        # Construct the command to run Blender in the background
        command = [
            "blender",
            "--background",
            "--python",
            blender_script_path,
            "--",
            "--model",
            model_path,
            "--out",
            output_dir,
            "--views",
            "12",
            "--res",
            "800",
            "--transparent",
            "--ortho",
        ]

        print("Running Blender command:")
        print(" ".join(command))

        # Execute the command
        subprocess.run(command, check=True)

        print(f"\nSuccessfully rendered {model_path}")
        print(f"Renders saved in: {output_dir}")

    except subprocess.CalledProcessError as e:
        print(f"Error during rendering: {e}")
    except FileNotFoundError:
        print("Error: 'blender' command not found.")
        print("Please make sure Blender is installed and accessible in your system's PATH.")

if __name__ == "__main__":
    # This is an example of how to use the render_model function.
    # You would replace this with the actual path to your model.
    # For this example to run, we need a model file.
    # I will create a dummy file for demonstration purposes.

    print("Creating a dummy model file for demonstration...")
    dummy_model_path = "dummy_model.stl"
    with open(dummy_model_path, "w") as f:
        f.write("solid A\nendsolid A\n")

    print(f"Dummy model file created at: {dummy_model_path}")

    # Get the absolute path for the model
    absolute_model_path = os.path.abspath(dummy_model_path)

    render_model(absolute_model_path)
