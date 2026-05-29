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
            if (m_dialogueVM.IsDisplayingChoices)
            {
                if (Keyboard.current != null)
                {
                    if (Keyboard.current.digit1Key.wasPressedThisFrame)
                    {
                        m_dialogueVM.SelectChoice(1);
                    }
                    else if (Keyboard.current.digit2Key.wasPressedThisFrame)
                    {
                        m_dialogueVM.SelectChoice(2);
                    }
                    else if (Keyboard.current.digit3Key.wasPressedThisFrame)
                    {
                        m_dialogueVM.SelectChoice(3);
                    }
                    else if (Keyboard.current.digit4Key.wasPressedThisFrame)
                    {
                        m_dialogueVM.SelectChoice(4);
                    }
                }
                return;
            }

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
