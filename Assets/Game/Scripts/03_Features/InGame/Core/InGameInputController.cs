using UnityEngine;
using UnityEngine.InputSystem;
using VContainer.Unity;

namespace Features.InGame
{
    public class InGameInputController : ITickable
    {
        private readonly IDialogueViewModel m_dialogueVM;

        public InGameInputController(IDialogueViewModel dialogueVM)
        {
            m_dialogueVM = dialogueVM;
        }

        public void Tick()
        {
            if (Keyboard.current != null && Keyboard.current.spaceKey.wasPressedThisFrame)
            {
                if (m_dialogueVM.IsTyping)
                {
                    m_dialogueVM.RequestSkip();
                }
                else
                {
                    m_dialogueVM.RequestNext();
                }
            }
        }
    }
}
