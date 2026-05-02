using UnityEngine;
using VContainer.Unity;

namespace Features.InGame
{
    public class InGameInputController : ITickable
    {
        private readonly IUIVisibilityViewModel m_visibilityVM;

        public InGameInputController(IUIVisibilityViewModel visibilityVM)
        {
            m_visibilityVM = visibilityVM;
        }

        public void Tick()
        {
            if (Input.GetKeyDown(KeyCode.H))
            {
                m_visibilityVM.ToggleVisibility();
            }
        }
    }
}
