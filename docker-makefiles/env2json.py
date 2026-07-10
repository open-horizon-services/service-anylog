# python3 env2json.py [INPUT_DIR] [ROOT_DIR] [TAG]
import os
import ast
import json
import sys

# args: [INPUT_DIR] [ROOT_DIR] [TAG]
_root_default = os.path.dirname(__file__).split("docker-makefiles")[0]

TAG       = sys.argv[3] if len(sys.argv) == 4 else "pre-develop"
ROOT_DIR  = sys.argv[2] if len(sys.argv) >= 3 else _root_default
INPUT_DIR = sys.argv[1] if len(sys.argv) >= 2 else os.path.join(ROOT_DIR, "docker-makefiles", "anylog-generic")

# If INPUT_DIR was passed without the full path, assume it lives under docker-makefiles/
if "docker-makefiles" not in INPUT_DIR:
    INPUT_DIR = os.path.join(ROOT_DIR, "docker-makefiles", INPUT_DIR)

# TAG = "pre-develop" # <-- user input
SERVICE_DEFINITION = os.path.join(ROOT_DIR, "service.definition.json")
if not os.path.isfile(SERVICE_DEFINITION):
    raise FileNotFoundError(SERVICE_DEFINITION)
SERVICE_POLICY     = os.path.join(ROOT_DIR, "service.policy.json")
if not os.path.isfile(SERVICE_POLICY):
    raise FileNotFoundError(SERVICE_POLICY)
NODE_POLICY        = os.path.join(ROOT_DIR, "node.policy.json")
if not os.path.isfile(NODE_POLICY):
    raise FileNotFoundError(NODE_POLICY)

INPUT_DIR = os.path.join(ROOT_DIR, "docker-makefiles", "anylog-generic") # <-- user defined input
if not os.path.isdir(INPUT_DIR):
    raise NotADirectoryError(INPUT_DIR)
INPUT_ENV = os.path.join(INPUT_DIR, "node_configs.env")
if not os.path.isfile(INPUT_ENV):
    raise FileNotFoundError(INPUT_ENV)

OUTPUT_SERVICE_DEFINITION = os.path.join(INPUT_DIR, "service.definition.json")
OUTPUT_SERVICE_POLICY     = os.path.join(INPUT_DIR, "service.policy.json")
OUTPUT_NODE_POLICY        = os.path.join(INPUT_DIR, "node.policy.json")



def read_env():
    """
    Read content from node_configs.env files (ie INPUT_ENV)
    """
    configs = []
    comment = ""
    param = None
    value = None
    with open(INPUT_ENV, 'r') as f:
        for line in f.readlines():
            if line.strip():
                if line.startswith("#===") or line.startswith("#---"):
                   pass
                elif line.startswith('#'):
                    comment += line.strip()
                elif '=' in line:
                    param, value = line.split("=", 1)
            if comment and param and value:
                value = value.replace('\n', '').strip()
                if value:
                    try:
                        value = ast.literal_eval(value)
                    except:
                        pass

                value_type = "string"
                if isinstance(value, (int, float)):
                    value_type = "int"

                configs.append({
                    "name": param,
                    "label": comment.replace('#', '').replace('\n', ' ').strip(),
                    "type": value_type,
                    "value": value
                })
                comment = ""
                param = None
                value = None

    return configs

def update_service_definition(configs:list, image:str):
    """
    Based on sample JSON files for service.definition.json - create a corresponding JSON for the given node
    """
    with open(SERVICE_DEFINITION, 'r') as f:
        file_content = json.load(f)

    file_content["userInput"] = configs
    file_content["deployment"]["services"]["$SERVICE_NAME"]["image"] = f"{image}:{TAG}"

    with open(OUTPUT_SERVICE_DEFINITION, 'w') as f:
        json.dump(file_content, f, indent=2)

def update_service_policy(node_name:str):
    """
    Based on sample JSON files for service.policy.json - create a corresponding JSON for the given node
    """
    with open(SERVICE_POLICY, 'r') as f:
        file_content = json.load(f)
    file_content["constraints"] = [f"openhorizon.allowPrivileged == true AND purpose == {node_name}"]

    with open(OUTPUT_SERVICE_POLICY, 'w') as f:
        json.dump(file_content, f, indent=2)

def update_node_policy(node_name: str):
    """
    Based on sample JSON files for node.policy.json - create a corresponding JSON for the given node
    """
    with open(NODE_POLICY, 'r') as f:
        file_content = json.load(f)


    if file_content.get("properties") is not None:
        for index in range(len(file_content["properties"])):
            if file_content["properties"][index].get("name") == "purpose":
                file_content["properties"][index]["value"] = node_name

    with open(OUTPUT_NODE_POLICY, 'w') as f:
        json.dump(file_content, f, indent=2)


def main():
    configs = read_env()
    node_name = None
    image = None
    for config in configs:
        if "NODE_NAME" in list(config.values()):
            node_name = config.get("value")
        elif "IMAGE" in list(config.values()):
            image = config.get("value")
        if node_name and image:
            break
    if not image:
        image = "anylogco/anylog-network"
    if not node_name:
        node_name = "anylog-node"

    update_service_definition(configs=configs, image=image)
    update_service_policy(node_name=node_name)
    update_node_policy(node_name=node_name)


if __name__ == "__main__":
    main()