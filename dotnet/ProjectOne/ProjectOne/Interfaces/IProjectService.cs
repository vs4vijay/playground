using ProjectOne.Models;

namespace ProjectOne.Interfaces
{
    public interface IProjectService
    {
        Task<IEnumerable<Project>> GetProjects();
        Task<Project> GetProject(int id);
        Task<Project> PostProject(Project project);
        Task<bool> PutProject(int id, Project project);
        Task<bool> DeleteProject(int id);
    }
}
