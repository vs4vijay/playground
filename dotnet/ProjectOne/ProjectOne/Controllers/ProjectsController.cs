using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ProjectOne.Data;
using ProjectOne.Models;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace ProjectOne.Controllers
{
    [Route("api/v1/[controller]")]
    [ApiController]
    public class ProjectsController : ControllerBase
    {
        private readonly ProjectContext _context;

        public ProjectsController(ProjectContext context)
        {
            _context = context;
        }

        // GET: api/Projects
        [HttpGet]
        public async Task<ActionResult<ResponseDTO<IEnumerable<Project>>>> GetProjects()
        {
            var projects = await _context.Projects.ToListAsync();
            return Ok(new ResponseDTO<IEnumerable<Project>> { Data = projects });
        }

        // GET: api/Projects/5
        [HttpGet("{id}")]
        public async Task<ActionResult<ResponseDTO<Project>>> GetProject(int id)
        {
            var project = await _context.Projects.FindAsync(id);
            if (project == null)
            {
                return NotFound();
            }
            return Ok(new ResponseDTO<Project> { Data = project });
        }

        // POST: api/Projects
        [HttpPost]
        public async Task<ActionResult<ResponseDTO<Project>>> PostProject(Project project)
        {
            _context.Projects.Add(project);
            await _context.SaveChangesAsync();
            return CreatedAtAction(nameof(GetProject), new { id = project.Id }, new ResponseDTO<Project> { Data = project });
        }

        // PUT: api/Projects/5
        [HttpPut("{id}")]
        public async Task<IActionResult> PutProject(int id, Project project)
        {
            if (id != project.Id)
            {
                return BadRequest();
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
                    return NotFound();
                }
                else
                {
                    throw;
                }
            }

            return NoContent();
        }

        // DELETE: api/Projects/5
        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteProject(int id)
        {
            var project = await _context.Projects.FindAsync(id);
            if (project == null)
            {
                return NotFound();
            }

            _context.Projects.Remove(project);
            await _context.SaveChangesAsync();

            return NoContent();
        }

        private bool ProjectExists(int id)
        {
            return _context.Projects.Any(e => e.Id == id);
        }
    }
    public class ResponseDTO<T>
    {
        public T Data { get; set; }
    }
}
