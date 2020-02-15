#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

docker_overrides_compile() {
    run_script 'env_update'
    local DOCKER_OVERRIDES_DIR
    DOCKER_OVERRIDES_DIR=$(run_script 'env_get' DOCKEROVERRIDESDIR)
    local VALIDATION_ERRORS=0

    info "Running Docker Overrides Compiler"
    # Move the user's existing docker-compose.override.yml, if it exists
    if [[ -f "${SCRIPTPATH}/compose/docker-compose.override.yml" ]]; then
        if ! grep -q '# GENERATED BY DOCKSTARTER' "${SCRIPTPATH}/compose/docker-compose.override.yml"; then
            warn "Found user-created docker-compose.overrides.yml file. Moving to ${DOCKER_OVERRIDES_DIR}/original_overrides.yml"
            mv "${SCRIPTPATH}/compose/docker-compose.override.yml" "${DOCKER_OVERRIDES_DIR}/original_overrides.yml"
        fi
    fi
    # Check for the directory and files should this be used from the command line
    if [[ ! -d ${DOCKER_OVERRIDES_DIR} ]]; then
        error "${DOCKER_OVERRIDES_DIR}/ does not exist. Create it and populate it with files to validate."
        return
    fi
    if [[ $(find "${DOCKER_OVERRIDES_DIR}"/* -type f -prune | wc -l) -eq 0 ]]; then
        error "No YML files found in ${DOCKER_OVERRIDES_DIR}/ to compile."
        return
    fi
    info "Merging docker-compose.overrides.yml file."
    local RUNFILE
    RUNFILE=$(mktemp) || fatal "Failed to create temporary yml merge script."
    echo "#!/usr/bin/env bash" > "${RUNFILE}"
    {
        # Add header comments to the generated file
        echo "echo '################################################################' > ${SCRIPTPATH}/compose/docker-compose.override.yml"
        echo "echo '#                   GENERATED BY DOCKSTARTER                   #' >> ${SCRIPTPATH}/compose/docker-compose.override.yml"
        echo "echo '#                        DO NOT MODIFY!                        #' >> ${SCRIPTPATH}/compose/docker-compose.override.yml"
        echo "echo '# If you already had this file, it has been retained and moved #' >> ${SCRIPTPATH}/compose/docker-compose.override.yml"
        echo "echo '# See DockSTARTer documentation for more information           #' >> ${SCRIPTPATH}/compose/docker-compose.override.yml"
        echo "echo '# https://dockstarter.com/advanced/overrides/                  #' >> ${SCRIPTPATH}/compose/docker-compose.override.yml"
        echo "echo '################################################################' >> ${SCRIPTPATH}/compose/docker-compose.override.yml"
        # Merge any included yml
        echo '/usr/local/bin/yq-go m '\\
        echo "${SCRIPTPATH}/compose/.reqs/*.yml \\"
    } >> "${RUNFILE}"
    info "Required files included."

    info "Checking ${DOCKER_OVERRIDES_DIR}/ for valid .yml files"
    shopt -s dotglob
    while IFS= read -r path; do
        if [[ -f ${path} ]]; then
            if yq-go v "${path}" > /dev/null 2>&1; then
                echo "${path} \\" >> "${RUNFILE}"
                info "${path//${DOCKER_OVERRIDES_DIR}\//} included"
            else
                warn "${path//${DOCKER_OVERRIDES_DIR}\//} is not valid yml and has not been included. Please check your syntax."
                VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
            fi
        fi
    done < <(find "${DOCKER_OVERRIDES_DIR}"/* -type f -not -name "original_overrides.yml" -prune)
    shopt -u dotglob

    # Include the user's original overrides, if they existed
    if [[ -f ${DOCKER_OVERRIDES_DIR}/original_overrides.yml ]]; then
        if yq-go v "${DOCKER_OVERRIDES_DIR}/original_overrides.yml" > /dev/null 2>&1; then
            echo "${DOCKER_OVERRIDES_DIR}/original_overrides.yml \\" >> "${RUNFILE}"
        else
            warn "original_overrides.yml is not valid yml. Please check your syntax."
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        fi
    fi

    # TODO: Prompt user if there are validation errors
    # if [[ ${VALIDATION_ERRORS} -gt 0 ]]; then
    #
    # fi

    echo ">> ${SCRIPTPATH}/compose/docker-compose.override.yml" >> "${RUNFILE}"
    run_script 'install_yq'
    info "Running compiled script to merge docker-compose.overrides.yml file."
    bash "${RUNFILE}" > /dev/null 2>&1 || fatal "Failed to run yml merge script."
    rm -f "${RUNFILE}" || warn "Failed to remove temporary yml merge script."
    info "Merging docker-compose.override.yml complete."
}

test_docker_overrides_compile() {
    run_script 'docker_overrides_compile'
}
