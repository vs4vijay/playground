using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ProjectOne.Data;
using ProjectOne.DTOs;
using ProjectOne.Interfaces;
using ProjectOne.Models;
using ProjectOne.Services;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace ProjectOne.Controllers
{
    [Route("api/v1/[controller]")]
    [ApiController]
    public class ProjectsController : ControllerBase
    {
        private readonly IProjectService _service;

        public ProjectsController(IProjectService service)
        {
            _service = service;
        }

        // GET: api/v1/Projects
        [HttpGet]
        public async Task<ActionResult<ResponseDTO<IEnumerable<Project>>>> GetProjects()
        {
            var projects = await _service.GetProjects();
            return Ok(new ResponseDTO<IEnumerable<Project>> { Data = projects });
        }

        // GET: api/v1/Projects/5
        [HttpGet("{id}")]
        public async Task<ActionResult<ResponseDTO<Project>>> GetProject(int id)
        {
            var project = await _service.GetProject(id);
            if (project == null)
            {
                return NotFound();
            }
            return Ok(new ResponseDTO<Project> { Data = project });
        }

        // POST: api/v1/Projects
        [HttpPost]
        public async Task<ActionResult<ResponseDTO<Project>>> PostProject(Project project)
        {
            var createdProject = await _service.PostProject(project);
            return CreatedAtAction(nameof(GetProject), new { id = createdProject.Id }, new ResponseDTO<Project> { Data = createdProject });
        }

        // PUT: api/v1/Projects/5
        [HttpPut("{id}")]
        public async Task<IActionResult> PutProject(int id, Project project)
        {
            var result = await _service.PutProject(id, project);
            if (!result)
            {
                return BadRequest();
            }
            return NoContent();
        }

        // DELETE: api/v1/Projects/5
        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteProject(int id)
        {
            var result = await _service.DeleteProject(id);
            if (!result)
            {
                return NotFound();
            }
            return NoContent();
        }
    }
}
