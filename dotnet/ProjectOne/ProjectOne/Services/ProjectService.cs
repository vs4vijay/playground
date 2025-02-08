using Microsoft.EntityFrameworkCore;
using ProjectOne.Data;
using ProjectOne.Interfaces;
using ProjectOne.Models;

namespace ProjectOne.Services
{
    public class ProjectService : IProjectService
    {
        private readonly ProjectContext _context;
        private readonly ILogger<ProjectService> _logger;

        public ProjectService(ProjectContext context, ILogger<ProjectService> logger)
        {
            _context = context;
            _logger = logger;
        }

        public async Task<IEnumerable<Project>> GetProjects()
        {
            _logger.LogInformation("Getting all projects");
            return await _context.Projects.ToListAsync();
        }

        public async Task<Project> GetProject(int id)
        {
            _logger.LogInformation("Getting project with id {Id}", id);
            return await _context.Projects.FindAsync(id);
        }

        public async Task<Project> PostProject(Project project)
        {
            _logger.LogInformation("Posting a new project");
            _context.Projects.Add(project);
            await _context.SaveChangesAsync();
            return project;
        }

        public async Task<bool> PutProject(int id, Project project)
        {
            if (id != project.Id)
            {
                _logger.LogWarning("Project id {Id} does not match the provided project id {ProjectId}", id, project.Id);
                return false;
            }

            _context.Entry(project).State = EntityState.Modified;

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!ProjectExists(id))
                {
                    _logger.LogWarning("Project with id {Id} does not exist", id);
                    return false;
                }
                else
                {
                    _logger.LogError("Concurrency exception occurred while updating project with id {Id}", id);
                    throw;
                }
            }

            _logger.LogInformation("Updated project with id {Id}", id);
            return true;
        }

        public async Task<bool> DeleteProject(int id)
        {
            var project = await _context.Projects.FindAsync(id);
            if (project == null)
            {
                _logger.LogWarning("Project with id {Id} not found", id);
                return false;
            }

            _context.Projects.Remove(project);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Deleted project with id {Id}", id);
            return true;
        }

        private bool ProjectExists(int id)
        {
            return _context.Projects.Any(e => e.Id == id);
        }
    }
}
