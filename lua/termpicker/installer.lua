---@class TermpickerInstaller
---@field termpicker_exists fun(): boolean Check if termpicker binary is available
---@field termpicker_path fun(): string|nil Get the path to termpicker binary if it exists
---@field install_termpicker fun(): boolean Install termpicker binary
local M = {}

-- Private variable to cache the termpicker path
local cached_termpicker_path = nil

---Get the XDG_DATA_HOME directory or fallback to ~/.local/share
---@return string data_home The XDG data home directory
local function get_xdg_data_home()
	local xdg_data = vim.env.XDG_DATA_HOME
	if xdg_data and xdg_data ~= '' then
		return xdg_data
	end
	return vim.fn.expand('~/.local/share')
end

---Get the local termpicker installation directory
---@return string local_dir The local installation directory
local function get_local_install_dir()
	return get_xdg_data_home() .. '/nvim/termpicker'
end

---Execute a shell command and return its success status and output
---@param cmd string The command to execute
---@return boolean success Whether the command succeeded
---@return string output The command output
local function execute_command(cmd)
	local handle = io.popen(cmd .. ' 2>&1')
	if not handle then
		return false, 'Failed to execute command'
	end
	
	local output = handle:read('*a') or ''
	local success = handle:close()
	return success, output
end

---Check if a file exists and is executable
---@param path string The file path to check
---@return boolean exists True if file exists and is executable
local function is_executable(path)
	local stat = vim.loop.fs_stat(path)
	if not stat or stat.type ~= 'file' then
		return false
	end
	
	-- Check if file is executable
	local success, _ = execute_command('test -x "' .. path .. '"')
	return success
end

---Find termpicker binary in various locations
---@return string|nil path The path to termpicker binary if found
local function find_termpicker_binary()
	-- If we have a cached path, verify it's still valid
	if cached_termpicker_path and is_executable(cached_termpicker_path) then
		return cached_termpicker_path
	end
	
	-- Clear invalid cache
	cached_termpicker_path = nil
	
	-- 1. Check system PATH
	local success, output = execute_command('which termpicker')
	if success and output ~= '' then
		local path = output:gsub('%s+$', '') -- trim whitespace
		if is_executable(path) then
			cached_termpicker_path = path
			return path
		end
	end
	
	-- 2. Check GOPATH/bin
	local gopath = vim.env.GOPATH
	if gopath and gopath ~= '' then
		local gopath_binary = gopath .. '/bin/termpicker'
		if is_executable(gopath_binary) then
			cached_termpicker_path = gopath_binary
			return gopath_binary
		end
	end
	
	-- 3. Check default GOPATH (~/.go/bin or ~/go/bin)
	local home = vim.env.HOME
	if home then
		local default_gopaths = {
			home .. '/go/bin/termpicker',
			home .. '/.go/bin/termpicker'
		}
		
		for _, gopath_binary in ipairs(default_gopaths) do
			if is_executable(gopath_binary) then
				cached_termpicker_path = gopath_binary
				return gopath_binary
			end
		end
	end
	
	-- 4. Check local installation directory
	local local_binary = get_local_install_dir() .. '/termpicker'
	if is_executable(local_binary) then
		cached_termpicker_path = local_binary
		return local_binary
	end
	
	return nil
end

---Check if Go is available on the system
---@return boolean available True if Go is available
local function is_go_available()
	local success, _ = execute_command('which go')
	return success
end

---Get the current platform for binary downloads
---@return string|nil platform The platform string (e.g., 'linux-amd64', 'darwin-arm64')
local function get_platform()
	local os_name = vim.loop.os_uname().sysname:lower()
	local arch = vim.loop.os_uname().machine:lower()
	
	-- Normalize OS name
	local os_map = {
		linux = 'linux',
		darwin = 'darwin',
		windows = 'windows'
	}
	
	-- Normalize architecture
	local arch_map = {
		x86_64 = 'amd64',
		amd64 = 'amd64',
		arm64 = 'arm64',
		aarch64 = 'arm64',
		armv7l = 'arm',
		armv6l = 'arm'
	}
	
	local normalized_os = os_map[os_name]
	local normalized_arch = arch_map[arch]
	
	if not normalized_os or not normalized_arch then
		return nil
	end
	
	return normalized_os .. '-' .. normalized_arch
end

---Download and extract termpicker binary for the current platform
---@return boolean success True if installation succeeded
local function install_binary()
	local platform = get_platform()
	if not platform then
		vim.notify('Unsupported platform for binary installation', vim.log.levels.ERROR)
		return false
	end
	
	local install_dir = get_local_install_dir()
	local binary_path = install_dir .. '/termpicker'
	
	-- Create installation directory
	vim.fn.mkdir(install_dir, 'p')
	
	-- Download URL - this assumes GitHub releases follow a standard pattern
	local download_url = string.format(
		'https://github.com/ChausseBenjamin/termpicker/releases/latest/download/termpicker-%s.tar.gz',
		platform
	)
	
	-- Download the archive
	local temp_file = vim.fn.tempname() .. '.tar.gz'
	local download_cmd = string.format('curl -L -o "%s" "%s"', temp_file, download_url)
	
	vim.notify('Downloading termpicker binary...', vim.log.levels.INFO)
	local success, output = execute_command(download_cmd)
	
	if not success then
		vim.notify('Failed to download termpicker: ' .. output, vim.log.levels.ERROR)
		return false
	end
	
	-- Extract the archive
	local extract_cmd = string.format('tar -xzf "%s" -C "%s"', temp_file, install_dir)
	success, output = execute_command(extract_cmd)
	
	if not success then
		vim.notify('Failed to extract termpicker: ' .. output, vim.log.levels.ERROR)
		-- Cleanup temp file
		os.remove(temp_file)
		return false
	end
	
	-- Cleanup temp file
	os.remove(temp_file)
	
	-- Make sure the binary is executable
	execute_command('chmod +x "' .. binary_path .. '"')
	
	-- Verify installation
	if is_executable(binary_path) then
		cached_termpicker_path = binary_path
		vim.notify('Termpicker binary installed successfully to ' .. binary_path, vim.log.levels.INFO)
		return true
	else
		vim.notify('Installation completed but binary is not executable', vim.log.levels.ERROR)
		return false
	end
end

---Install termpicker using Go
---@return boolean success True if installation succeeded
local function install_with_go()
	vim.notify('Installing termpicker with Go...', vim.log.levels.INFO)
	local success, output = execute_command('go install github.com/ChausseBenjamin/termpicker@latest')
	
	if success then
		-- Clear cache to force re-detection
		cached_termpicker_path = nil
		local path = find_termpicker_binary()
		if path then
			vim.notify('Termpicker installed successfully with Go to ' .. path, vim.log.levels.INFO)
			return true
		else
			vim.notify('Go installation succeeded but binary not found in expected locations', vim.log.levels.WARN)
			return false
		end
	else
		vim.notify('Failed to install termpicker with Go: ' .. output, vim.log.levels.ERROR)
		return false
	end
end

---Check if termpicker binary exists and is accessible
---@return boolean exists True if termpicker is available
function M.termpicker_exists()
	return find_termpicker_binary() ~= nil
end

---Get the path to the termpicker binary
---@return string|nil path The path to termpicker binary if it exists
function M.termpicker_path()
	return find_termpicker_binary()
end

---Install termpicker binary
---Tries Go installation first, falls back to binary download
---@return boolean success True if installation succeeded
function M.install_termpicker()
	-- Check if already installed
	if M.termpicker_exists() then
		vim.notify('Termpicker is already installed at ' .. M.termpicker_path(), vim.log.levels.INFO)
		return true
	end
	
	-- Try Go installation first
	if is_go_available() then
		if install_with_go() then
			return true
		end
		vim.notify('Go installation failed, trying binary download...', vim.log.levels.WARN)
	else
		vim.notify('Go not found, using binary download...', vim.log.levels.INFO)
	end
	
	-- Fall back to binary installation
	return install_binary()
end

return M